copy_script:
  file.managed:
    - name: /home/nttrmadm/sap_instances.sh
    - source: salt://sap_instances.sh
    - mode: 744

execute_script:
  cmd.run:
    - name: '/home/nttrmadm/sap_instances.sh {{ pillar.get('command') }} {{ pillar.get('SID') }}'