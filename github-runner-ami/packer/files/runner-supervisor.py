#!/usr/bin/env python3
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
"""
Obtain credentials for Actions runner and co-operate with auto scaling group

The purpose of this script is to enable the self-hosted runners to operate in
an AutoScaling environment (without needing admin permissions on the GitHub
repo to create and delete runners.)

The order of operations is:

1. Obtain credentials

   We have pre-created a number of credentials and stored them in Amazon KMS.
   This script makes use of dynamodb to obtain an exclusive lock on a set of
   credentials.

   We need the "locking" as if you use credentials that are already
   in use the new runner process will wait (but never error) until they are not
   in use.

2. Complete the ASG lifecycle action so the instance is marked as InService

   This might not be strictly necessary, we don't want the instance to be "in
   service" until the runner has started.

3. Emit metric saying whether instance is running a job or not

   This is used to drive the scale-in CloudWatch alarm

4. Monitor for the runner starting jobs, and protecting the instance from Scale-In when it is

   Since we are running in an autoscaling group we can't dictate which instance
   AWS choses to terminate, so we instead have to set scale-in protection when a job is running.

   The way we watch for jobs being executed is using the Netlink Process
   Connector, which is a datagram socket that a (root) process can open to the
   kernel, to receive push events for whenever a process starts or stops.

   There are more events than that send, and to limit it to the only ones we
   care about we use a BPF filter to drop everything else.

   Since it is a datagram socket it is possible we might miss a notification, so
   we also periodically check if the process is still alive

5. Watch for ASG instance state changing to Terminating:Wait

   When the ASG wants to terminate the instance, we have it configured to put
   the instance in to a "requested" state -- this is to avoid a race condition
   where the instance _isn't_ running a job (so isn't protected from scale in),
   gets set to Terminating, but before AWS shuts down the machine the runner
   process picks up and starts a Job, which leads to the job failing with "The
   self-hosted runner: Airflow Runner $N lost communication with the server".

   When we notice being in this state, we _gracefully_ shut down the runner
   (letting it complete any job it might have), stop it from restarting, and
   then allow the termination lifecycle to continue

"""
import ctypes
import datetime
import enum
import errno
import json
import logging
import os
import random
import selectors
import shutil
import signal
import socket
from subprocess import check_call
from typing import Callable, List, Tuple, Union

import boto3
import click
import psutil
from python_dynamodb_lock.python_dynamodb_lock import DynamoDBLockClient, DynamoDBLockError
from tenacity import before_sleep_log, retry, stop_after_delay, wait_exponential

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)
log.setLevel(logging.DEBUG)

logging.getLogger('python_dynamodb_lock').setLevel(logging.WARNING)


TABLE_NAME = os.getenv('COUNTER_TABLE', 'GithubRunnerQueue')


@click.command()
@click.option('--repo', default='apache/airflow')
@click.option('--user', default='runner')
@click.option(
    '--output-folder',
    help="Folder to write credentials to. Default of ~runner/actions-runner",
    default='~runner/actions-runner',
)
def main(repo, output_folder, user):
    global INSTANCE_ID
    # Notify the ASG LifeCycle hook that we are now In Service and ready to
    # process requests/safe to be shut down

    # Fetch current instance ID from where cloutinit writes it to
    if not INSTANCE_ID:
        with open('/var/lib/cloud/data/instance-id') as fh:
            INSTANCE_ID = fh.readline().strip()

    log.info("Starting on %s...", INSTANCE_ID)

    output_folder = os.path.expanduser(output_folder)

    short_time = datetime.timedelta(microseconds=1)

    dynamodb = boto3.resource('dynamodb')
    client = DynamoDBLockClient(
        dynamodb,
        table_name='GitHubRunnerLocks',
        expiry_period=datetime.timedelta(0, 300),
        heartbeat_period=datetime.timedelta(seconds=10),
    )

    # Just keep trying until we get some credentials.
    while True:
        # Have each runner try to get a credential in a random order.
        possibles = get_possible_credentials(repo)
        random.shuffle(possibles)

        log.info("Trying to get a set of credentials in this order: %r", possibles)

        notify = get_sd_notify_func()

        for index in possibles:
            try:
                lock = client.acquire_lock(
                    f'{repo}/{index}',
                    retry_period=short_time,
                    retry_timeout=short_time,
                    raise_context_exception=True,
                )
            except DynamoDBLockError as e:
                log.info("Could not lock %s (%s)", index, e)
                continue

            with lock:
                log.info("Obtained lock on %s", index)
                write_credentials_to_files(repo, index, output_folder, user)
                merge_in_settings(repo, output_folder)
                notify(f"STATUS=Obtained lock on {index}")

                if get_lifecycle_state() == "Pending:Wait":
                    complete_asg_lifecycle_hook()

                notify("READY=1")
                log.info("Watching for Runner.Worker processes")
                ProcessWatcher().run()

            client.close()

            exit()


def get_sd_notify_func() -> Callable[[str], None]:
    # http://www.freedesktop.org/software/systemd/man/sd_notify.html
    addr = os.getenv('NOTIFY_SOCKET')
    if not addr:
        return lambda status: None

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    if addr[0] == '@':
        addr = '\0' + addr[1:]
    sock.connect(addr)

    def notify(status: str):
        sock.sendall(status.encode('utf-8'))

    return notify


def write_credentials_to_files(
    repo: str, index: str, out_folder: str = '~runner/actions-runner', user: str = 'runner'
):
    param_path = os.path.join('/runners/', repo, index)

    resp = boto3.client("ssm").get_parameters_by_path(Path=param_path, Recursive=False, WithDecryption=True)

    param_to_file = {
        'config': '.runner',
        'credentials': '.credentials',
        'rsaparams': '.credentials_rsaparams',
    }

    for param in resp['Parameters']:
        # "/runners/apache/airflow/config" -> "config"
        name = os.path.basename(param['Name'])
        filename = param_to_file.get(name, None)
        if filename is None:
            log.info("Unknown Parameter from SSM: %r", param['Name'])
            continue
        log.info("Writing %r to %r", param['Name'], filename)
        with open(os.path.join(out_folder, filename), "w") as fh:
            fh.write(param['Value'])
            shutil.chown(fh.name, user)
            os.chmod(fh.name, 0o600)
        del param_to_file[name]
    if param_to_file:
        raise RuntimeError(f"Missing expected params: {list(param_to_file.keys())}")


def merge_in_settings(repo: str, out_folder: str) -> None:
    client = boto3.client('ssm')

    param_path = os.path.join('/runners/', repo, 'configOverlay')
    log.info("Loading config overlay from %s", param_path)

    try:

        resp = client.get_parameter(Name=param_path, WithDecryption=True)
    except client.exceptions.ParameterNotFound:
        log.debug("Failed to load config overlay", exc_info=True)
        return

    try:
        overlay = json.loads(resp['Parameter']['Value'])
    except ValueError:
        log.debug("Failed to parse config overlay", exc_info=True)
        return

    with open(os.path.join(out_folder, ".runner"), "r+") as fh:
        settings = json.load(fh)

        for key, val in overlay.items():
            settings[key] = val

        fh.seek(0, os.SEEK_SET)
        os.ftruncate(fh.fileno(), 0)
        json.dump(settings, fh, indent=2)


def get_possible_credentials(repo: str) -> List[str]:
    client = boto3.client("ssm")
    paginator = client.get_paginator("describe_parameters")

    path = os.path.join('/runners/', repo, '')
    baked_path = os.path.join(path, 'runnersList')

    # Pre-compute the list, to avoid making lots of requests and getting throttled by SSM API in case of
    # thundering herd
    try:
        log.info("Using pre-computed credentials indexes from %s", baked_path)
        resp = client.get_parameter(Name=baked_path)
        return resp['Parameter']['Value'].split(',')
    except client.exceptions.ParameterNotFound:
        pass

    log.info("Looking at %s for possible credentials", path)

    pages = paginator.paginate(
        ParameterFilters=[{"Key": "Path", "Option": "Recursive", "Values": [path]}],
        PaginationConfig={
            "PageSize": 50,
        },
    )

    seen = set()

    for i, page in enumerate(pages):
        log.info("Page %d", i)
        for param in page['Parameters']:
            name = param['Name']
            log.info("%s", name)

            # '/runners/x/1/config' -> '1/config',
            # '/runners/x/y/1/config' -> 'y/1/config',
            local_name = name[len(path) :]

            try:
                # '1/config' -> '1'
                index, _ = local_name.split('/')
            except ValueError:
                # Ignore any 'x/y' when we asked for 'x'. There should only be an index and a filename
                log.debug("Ignoring nested path %s", name)
                continue

            try:
                # Check it's a number, but keep variable as string
                int(index)
            except ValueError:
                log.debug("Ignoring non-numeric index %s", name)
                continue

            index = os.path.basename(os.path.dirname(name))
            seen.add(index)

    if not seen:
        raise RuntimeError(f'No credentials found in SSM ParameterStore for {repo!r}')

    try:
        resp = client.put_parameter(
            Name=baked_path, Type='StringList', Value=','.join(list(seen)), Overwrite=False
        )
        log.info("Stored pre-computed credentials indexes at %s", baked_path)
    except client.exceptions.ParameterAlreadyExists:
        # Race, we lost, never mind!
        pass

    return list(seen)


OWN_ASG = None
INSTANCE_ID = None


def get_lifecycle_state() -> str:
    global INSTANCE_ID, OWN_ASG

    if not INSTANCE_ID:
        with open('/var/lib/cloud/data/instance-id') as fh:
            INSTANCE_ID = fh.readline().strip()

    asg_client = boto3.client('autoscaling')

    try:
        instances = asg_client.describe_auto_scaling_instances(
            InstanceIds=[INSTANCE_ID],
        )['AutoScalingInstances']
    except asg_client.exceptions.ClientError:
        return "UNKNOWN"

    if len(instances) != 1:
        return "UNKNOWN"

    details = instances[0]

    if not OWN_ASG:
        OWN_ASG = details['AutoScalingGroupName']

    return details['LifecycleState']


def complete_asg_lifecycle_hook(hook_name='WaitForInstanceReportReady', retry=False):
    global OWN_ASG, INSTANCE_ID
    # Notify the ASG LifeCycle hook that we are now InService and ready to
    # process requests/safe to be shut down

    asg_client = boto3.client('autoscaling')

    try:
        asg_client.complete_lifecycle_action(
            AutoScalingGroupName=OWN_ASG,
            InstanceId=INSTANCE_ID,
            LifecycleHookName=hook_name,
            LifecycleActionResult='CONTINUE',
        )
        log.info("LifeCycle hook %s set to CONTINUE instance=%s", hook_name, INSTANCE_ID)
    except asg_client.exceptions.ClientError as e:
        # If the script fails for whatever reason and we re-run, the lifecycle hook may have already be
        # completed, so this would fail. That is not an error

        # We don't want the stacktrace here, just the message
        log.warning("Failed to complete lifecycle hook %s: %s", hook_name, str(e))
        pass


# Constants and types from
# https://github.com/torvalds/linux/blob/fcadab740480e0e0e9fa9bd272acd409884d431a/include/uapi/linux/cn_proc.h
class NlMsgFlag(enum.IntEnum):
    NoOp = 1
    Error = 2
    Done = 3
    Overrun = 4


class NLMsgHdr(ctypes.Structure):
    """Netlink Message Header"""

    _fields_ = [
        ("len", ctypes.c_uint32),
        ("type", ctypes.c_uint16),
        ("flags", ctypes.c_uint16),
        ("seq", ctypes.c_uint32),
        ("pid", ctypes.c_uint32),
    ]


class ProcConnectorOp(enum.IntEnum):
    MCAST_LISTEN = 1
    MCAST_IGNORE = 2


class cn_msg(ctypes.Structure):
    """Linux kernel Connector message"""

    CN_IDX_PROC = 1
    CN_VAL_PROC = 1

    _fields_ = [
        ("cb_id_idx", ctypes.c_uint32),
        ("cb_id_val", ctypes.c_uint32),
        ("seq", ctypes.c_uint32),
        ("ack", ctypes.c_uint32),
        ("len", ctypes.c_uint16),
        ("flags", ctypes.c_uint16),
    ]

    def __init__(self, header, data, **kwargs):
        super().__init__(**kwargs)
        self.header = header
        self.len = ctypes.sizeof(data)
        self.data = data
        self.header.len = ctypes.sizeof(header) + ctypes.sizeof(self) + self.len

    def to_bytes(self):
        return bytes(self.header) + bytes(self) + bytes(self.data)  # type: ignore


class ProcEventWhat(enum.IntFlag):
    NONE = 0x0
    FORK = 0x1
    EXEC = 0x2
    UID = 0x4
    GID = 0x40
    SID = 0x80
    PTRACE = 0x0000010
    COMM = 0x0000020
    COREDUMP = 0x40000000
    EXIT = 0x80000000


class proc_event(ctypes.Structure):
    """Base proc_event field"""

    _fields_ = [
        ("what", ctypes.c_uint32),
        ("cpu", ctypes.c_uint32),
        ("timestamp", ctypes.c_uint64),  # Number of nano seconds since system boot
    ]

    @classmethod
    def from_netlink_packet(
        cls, data
    ) -> Tuple["proc_event", Union[None, "exec_proc_event", "exit_proc_event"]]:
        """
        Parse the netlink packet in to a
        """
        # Netlink message header (struct nlmsghdr)
        header = NLMsgHdr.from_buffer_copy(data)
        data = data[ctypes.sizeof(header) :]

        # We already checked/filtered on header.type == NlMsgFlag.Done

        # Connector message header (struct cn_msg)
        connector_msg = cn_msg.from_buffer_copy(data)

        # Ignore messages from other Netlink connector types: done via BPF

        data = data[ctypes.sizeof(connector_msg) :]

        event = proc_event.from_buffer_copy(data)
        data = data[ctypes.sizeof(event) :]
        event.what = ProcEventWhat(event.what)

        if event.what == ProcEventWhat.EXEC:
            return event, exec_proc_event.from_buffer_copy(data)
        elif event.what == ProcEventWhat.EXIT:
            return event, exit_proc_event.from_buffer_copy(data)
        return event, None


class exec_proc_event(ctypes.Structure):
    _fields_ = [
        ("pid", ctypes.c_int32),
        ("tid", ctypes.c_int32),
    ]


class exit_proc_event(ctypes.Structure):
    _fields_ = [
        ("pid", ctypes.c_int32),
        ("tid", ctypes.c_int32),
        ("exit_code", ctypes.c_int32),
        ("signal", ctypes.c_int32),
    ]


class ProcessWatcher:
    interesting_processes = {}

    protected = None
    in_termating_lifecycle = False

    def run(self):
        # Create a signal pipe that we can poll on
        sig_read, sig_write = socket.socketpair()

        sel = selectors.DefaultSelector()

        def sig_handler(signal, frame):
            # no-op
            ...

        sig_read.setblocking(False)
        sig_write.setblocking(False)
        sel.register(sig_read, selectors.EVENT_READ, None)

        proc_socket = self.open_proc_connector_socket()
        proc_socket.setblocking(False)

        signal.signal(signal.SIGINT, sig_handler)
        signal.signal(signal.SIGALRM, sig_handler)
        signal.setitimer(signal.ITIMER_REAL, 30, 30.0)
        signal.set_wakeup_fd(sig_write.fileno(), warn_on_full_buffer=False)

        sel.register(proc_socket, selectors.EVENT_READ, self.handle_proc_event)

        self.pgrep()

        try:
            while True:
                for key, mask in sel.select():

                    if key.fileobj == sig_read:
                        sig = signal.Signals(key.fileobj.recv(1)[0])  # type: ignore
                        if sig == signal.SIGALRM:
                            self.check_still_alive()
                            continue
                        else:
                            log.info(f"Got {sig.name}, exiting")
                            return
                    callback = key.data
                    callback(key.fileobj, mask)
        finally:
            # Disable the timers for any cleanup code to run
            signal.setitimer(signal.ITIMER_REAL, 0)
            signal.set_wakeup_fd(-1)

    def pgrep(self):
        """Check for any interesting processes we might have missed."""
        listener_found = False

        for proc in psutil.process_iter(['name', 'cmdline']):
            try:
                if proc.name() == "Runner.Worker" and proc.pid not in self.interesting_processes:
                    log.info(
                        "Found existing interesting processes, protecting from scale in %d: %s",
                        proc.pid,
                        proc.cmdline(),
                    )
                    self.interesting_processes[proc.pid] = proc
                    self.protect_from_scale_in(protect=True)
                    self.dynamodb_atomic_decrement()
                if proc.name() == "Runner.Listener":
                    listener_found = True
            except psutil.NoSuchProcess:
                # Process went away before we could
                pass

        if not listener_found:
            if self.in_termating_lifecycle:
                log.info("Runner.Listener process not found - OkayToTerminate instance")
                complete_asg_lifecycle_hook('OkayToTerminate')
            else:
                # Unprotect ourselves if somehow the runner is no longer working
                self.protect_from_scale_in(protect=False)

    def check_still_alive(self):
        # Check ASG status
        if not self.in_termating_lifecycle:
            state = get_lifecycle_state()
            if state == 'Terminating:Wait':
                self.in_termating_lifecycle = True
                self.gracefully_terminate_runner()
            elif state == 'Pending:Wait':
                complete_asg_lifecycle_hook()

        # proc_connector is un-reliable (UDP) so periodically check if the processes are still alive
        if not self.interesting_processes:
            self.pgrep()
            return

        # list() is used to prevent "Dict changed size during iteration" during loop below
        pids = list(self.interesting_processes.keys())
        log.info("Checking processes %r are still alive", pids)

        for pid in pids:
            proc = self.interesting_processes[pid]
            if not proc.is_running() or proc.status() == psutil.STATUS_ZOMBIE:
                log.info("Proc %d dead but we didn't notice!", pid)
                del self.interesting_processes[pid]

        if not self.interesting_processes:
            log.info("No interesting processes left, unprotecting from scale in")
            self.protect_from_scale_in(protect=False)
        elif not self.protected:
            # If we didn't manage to protect last time, try again
            self.protect_from_scale_in()

    def gracefully_terminate_runner(self):
        check_call(['systemctl', 'stop', 'actions.runner', '--no-block'])

    def protect_from_scale_in(self, protect: bool = True):
        """ Set (or unset) ProtectedFromScaleIn on our instance"""
        if not OWN_ASG:
            # Not part of an ASG
            return

        if self.in_termating_lifecycle:
            log.info("Not trying to SetInstanceProtection, we are already in the terminating lifecycle step")
            return

        asg_client = boto3.client('autoscaling')
        try:
            self._protect_from_scale_in(asg_client, protect)
            self.protected = protect
        except asg_client.exceptions.ClientError as e:
            # This can happen if this the runner picks up a job "too quick", and the ASG still has the state
            # as Pending:Proceed, so we can't yet set it as protected
            log.warning("Failed to set scale in protection: %s", str(e))

    @retry(
        wait=wait_exponential(multiplier=1, max=10),
        stop=stop_after_delay(30),
        before_sleep=before_sleep_log(log, logging.INFO),
        reraise=True,
    )
    def _protect_from_scale_in(self, asg_client, protect):
        asg_client.set_instance_protection(
            AutoScalingGroupName=OWN_ASG,
            InstanceIds=[INSTANCE_ID],
            ProtectedFromScaleIn=protect,
        )

    def dynamodb_atomic_decrement(self):
        dynamodb = boto3.client('dynamodb')
        try:
            resp = dynamodb.update_item(
                TableName=TABLE_NAME,
                Key={'id': {'S': 'queued_jobs'}},
                ExpressionAttributeValues={':delta': {'N': '-1'}, ':limit': {'N': '0'}},
                UpdateExpression='ADD queued :delta',
                # Make sure it never goes below zero!
                ConditionExpression='queued > :limit',
                ReturnValues='UPDATED_NEW',
            )

            log.info("Updated DynamoDB queue length: %s", resp['Attributes']['queued']['N'])
        except dynamodb.exceptions.ConditionalCheckFailedException:
            log.warning("%s.queued was already 0, we won't decrease it any further!", TABLE_NAME)

    def handle_proc_event(self, sock, mask):
        try:
            data, (nlpid, nlgrps) = sock.recvfrom(1024)
        except OSError as e:
            if e.errno == errno.ENOBUFS:
                return
            raise
        if nlpid != 0:
            # Ignore messages from non-root processes
            return

        event, detail = proc_event.from_netlink_packet(data)
        if event.what == ProcEventWhat.EXEC:
            try:
                proc = psutil.Process(detail.pid)

                with proc.oneshot():
                    if proc.name() == "Runner.Worker":
                        log.info(
                            "Found new interesting processes, protecting from scale in %d: %s",
                            detail.pid,
                            proc.cmdline(),
                        )
                        self.interesting_processes[detail.pid] = proc
                        self.protect_from_scale_in(protect=True)
                        self.dynamodb_atomic_decrement()

            except psutil.NoSuchProcess:
                # We lost the race, process has already exited. If it was that short lived it wasn't that
                # interesting anyway
                pass
        elif event.what == ProcEventWhat.EXIT:
            if detail.pid in self.interesting_processes:
                log.info("Interesting process %d exited", detail.pid)
                del self.interesting_processes[detail.pid]

                if not self.interesting_processes:
                    log.info("Watching no processes, disabling termination protection")
                    self.protect_from_scale_in(protect=False)
            elif self.in_termating_lifecycle:
                try:
                    proc = psutil.Process(detail.pid)
                    if proc.name() == "Runner.Listener":
                        log.info("Runner.Listener process %d exited - OkayToTerminate instance", detail.pid)
                        complete_asg_lifecycle_hook('OkayToTerminate')
                except psutil.NoSuchProcess:
                    # We lost the race, process has already exited. If it was that short lived it wasn't that
                    # interesting anyway
                    pass

    def open_proc_connector_socket(self) -> socket.socket:
        """Open and set up a socket connected to the kernel's Proc Connector event stream

        This uses the Netlink family of socket, the Connector message type and the proc_event connector to get
        send a (UDP) message whenever a process starts or exits.

        We use this mechansim to get notified when processes start or stop, so we can watch for the
        "Runner.Worker" and enable/disable termination protection.
        """

        class bpf_insn(ctypes.Structure):
            """"The BPF instruction data structure"""

            _fields_ = [
                ("code", ctypes.c_ushort),
                ("jt", ctypes.c_ubyte),
                ("jf", ctypes.c_ubyte),
                ("k", ctypes.c_uint32),
            ]

        class bpf_program(ctypes.Structure):
            """"Structure for BIOCSETF"""

            _fields_ = [("bf_len", ctypes.c_uint), ("bf_insns", ctypes.POINTER(bpf_insn))]

            def __init__(self, program):
                self.bf_len = len(program)
                bpf_insn_array = bpf_insn * self.bf_len
                self.bf_insns = bpf_insn_array()

                # Fill the pointer
                for i, insn in enumerate(program):
                    self.bf_insns[i] = insn

        def bpf_jump(code, k, jt, jf) -> bpf_insn:
            """
            :param code: BPF instruction op codes
            :param k: argument
            :param jt: jump offset if true
            :param jf: jump offset if false
            """
            return bpf_insn(code, jt, jf, k)

        def bpf_stmt(code, k):
            return bpf_jump(code, k, 0, 0)

        def packet_filter_prog():
            """
            A Berkley Packet Filter program to filter down the "firehose" of info we receive over the netlink
            socket.

            The Proc Connector doesn't provide any easy way to filter out the firehose of package events, and
            while we could ignore the things we don't care about in Python, it's more efficient to never
            receive those packets. "Luckily" there is the BPF, or Berkley Packet Filter, which can operate on
            any socket. This BPF program was taken from
            https://web.archive.org/web/20130601175512/https://netsplit.com/2011/02/09/the-proc-connector-and-socket-filters/
            """
            # A subset of Berkeley Packet Filter constants and macros, as defined in linux/filter.h.

            # Instruction classes
            BPF_LD = 0x00
            BPF_JMP = 0x05
            BPF_RET = 0x06

            # ld/ldx fields
            BPF_W = 0x00
            BPF_H = 0x08
            BPF_ABS = 0x20

            # alu/jmp fields
            BPF_JEQ = 0x10
            BPF_K = 0x00

            return bpf_program(
                [
                    # Load 16-bit ("half"-word) nlmsg.type field
                    bpf_stmt(BPF_LD | BPF_H | BPF_ABS, NLMsgHdr.type.offset),
                    bpf_jump(BPF_JMP | BPF_JEQ | BPF_K, socket.htons(NlMsgFlag.Done), 1, 0),
                    # Not NlMsgFlag.Done, return whole packet
                    bpf_stmt(BPF_RET | BPF_K, 0xFFFFFFFF),
                    #
                    # Load 32-bit (word) cb_id_idx field
                    bpf_stmt(BPF_LD | BPF_W | BPF_ABS, ctypes.sizeof(NLMsgHdr) + cn_msg.cb_id_idx.offset),
                    bpf_jump(BPF_JMP | BPF_JEQ | BPF_K, socket.htonl(cn_msg.CN_IDX_PROC), 1, 0),
                    # If not CN_IDX_PROC, return whole packet
                    bpf_stmt(BPF_RET | BPF_K, 0xFFFFFFFF),
                    #
                    # Load cb_id_val field
                    bpf_stmt(BPF_LD | BPF_W | BPF_ABS, ctypes.sizeof(NLMsgHdr) + cn_msg.cb_id_val.offset),
                    bpf_jump(BPF_JMP | BPF_JEQ | BPF_K, socket.htonl(cn_msg.CN_VAL_PROC), 1, 0),
                    # If not CN_VAL_PROC, return whole packet
                    bpf_stmt(BPF_RET | BPF_K, 0xFFFFFFFF),
                    #
                    # If not ProcEventWhat.EXEC or ProcEventWhat.EXIT, event, filter out the packet
                    bpf_stmt(
                        BPF_LD | BPF_W | BPF_ABS,
                        ctypes.sizeof(NLMsgHdr) + ctypes.sizeof(cn_msg) + proc_event.what.offset,
                    ),
                    bpf_jump(BPF_JMP | BPF_JEQ | BPF_K, socket.htonl(ProcEventWhat.EXEC), 2, 0),
                    bpf_jump(BPF_JMP | BPF_JEQ | BPF_K, socket.htonl(ProcEventWhat.EXIT), 1, 0),
                    bpf_stmt(BPF_RET | BPF_K, 0x0),
                    # Return everything
                    bpf_stmt(BPF_RET | BPF_K, 0xFFFFFFFF),
                ]
            )

        # Create Netlink socket

        # Missing from most/all pythons
        NETLINK_CONNECTOR = getattr(socket, "NETLINK_CONNECTOR", 11)
        SO_ATTACH_FILTER = getattr(socket, "SO_ATTACH_FILTER", 26)

        sock = socket.socket(socket.AF_NETLINK, socket.SOCK_DGRAM, NETLINK_CONNECTOR)

        filter_prog = packet_filter_prog()
        sock.setsockopt(socket.SOL_SOCKET, SO_ATTACH_FILTER, bytes(filter_prog))  # type: ignore

        sock.bind((os.getpid(), cn_msg.CN_IDX_PROC))

        # Send PROC_CN_MCAST_LISTEN to start receiving messages
        msg = cn_msg(
            header=NLMsgHdr(type=NlMsgFlag.Done, pid=os.getpid()),
            cb_id_idx=cn_msg.CN_IDX_PROC,
            cb_id_val=cn_msg.CN_VAL_PROC,
            seq=0,
            ack=0,
            data=ctypes.c_uint32(ProcConnectorOp.MCAST_LISTEN),
        )

        data = msg.to_bytes()
        if sock.send(data) != len(data):
            raise RuntimeError("Failed to send PROC_CN_MCAST_LISTEN")

        return sock


if __name__ == "__main__":
    main()
