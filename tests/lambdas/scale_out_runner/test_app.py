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

import json

import pytest
from app import app  # noqa


@pytest.fixture(autouse=True)
def no_requests(monkeypatch):
    monkeypatch.setenv("GH_WEBHOOK_TOKEN", "abc")


def test_no_auth(client):
    response = client.http.post('/', body=json.dumps({'hello': 'world'}))
    assert response.status_code == 400


@pytest.mark.parametrize(
    "sig",
    [
        "md5=",
        # Valid, but not prefixed
        "160156e060356c9444613b224fc5613a0a25315b7898fd5d8c7656bd8a6654af",
    ],
)
def test_bad_auth(sig, client):
    response = client.http.post(
        '/',
        headers={
            'X-Hub-Signature-256': sig,
        },
        body=json.dumps({'hello': 'world'}),
    )
    assert response.status_code == 400


def test_auth(client):
    response = client.http.post(
        '/',
        headers={
            'X-Hub-Signature-256': 'sha256=160156e060356c9444613b224fc5613a0a25315b7898fd5d8c7656bd8a6654af'
        },
        body=json.dumps({'hello': 'world'}),
    )
    assert response.status_code == 200
