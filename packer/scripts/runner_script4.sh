mkdir -p /opt/ssd/hostedtoolcache /opt/sdd/work /opt/hostedtoolcache /home/runner/actions-runner/_work
echo '/opt/ssd/hostedtoolcache /opt/hostedtoolcache none defaults,bind 0 0' >> /etc/fstab
mount /opt/hostedtoolcache
echo '/opt/ssd/work /home/runner/actions-runner/_work none defaults,bind 0 0' >> /etc/fstab
mount /home/runner/actions-runner/_work
chown runner: /opt/ssd/work /home/runner/actions-runner/_work /opt/ssd/hostedtoolcache /opt/hostedtoolcache
systemctl enable --now iptables.service
systemctl enable actions.runner-credentials.service
systemctl enable --now actions.runner.service