# nfsu-lfir

```
ansible-playbook -i inventory/hosts.yml -l demo_hosts playbooks/setup_nginx_mirror.yml
ansible-playbook -i inventory/hosts.yml -l sources playbooks/setup_nginx_mirror.yml
ansible-playbook -i inventory/hosts.yml -l mirrors playbooks/setup_nginx_mirror.yml
```
