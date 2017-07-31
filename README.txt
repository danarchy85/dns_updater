DreamHost DNS Updater

$ ruby dns_updater.rb
Configuration not found. Creating a new one!
Only A records are supported at this time.
Enter your DreamHost API Key: API_KEY1

Enter domains to manage separated by commas:
Ex: domain1.tld,domain2.tld: domain1.tld, domain2.tld, domain3.tld
Added:  domain1.tld       => type: A
Added:  domain2.tld	  => type: A
Added:  domain3.tld	  => type: A
Do you need to add another DreamHost account/API key? (Y/N): y
Enter your DreamHost API Key: API_KEY2

Enter domains to manage separated by commas, no spaces:
Ex: domain1.tld,domain2.tld: domain1.tld
Added:  domain1.tld  => type: A
Do you need to add another DreamHost account/API key? (Y/N): n
Final configuration:
---
:pidfile: "/tmp/dnsupdater.pid"
:connections:
  API_KEY1:
    :domains:
      domain1.tld: A
      domain2.tld: A
      domain3.tld: A
  API_KEY2:
    :domains:
      domain1.tld: A


Does the above configuration look correct?: (Y/N): y
File saved to: /home/dan/.DH_DNS_Config!
No action provided! Running once to update all domains!
WAN IP: YOUR_WAN_IP
Checking domains for API key: API_KEY1
Checking: domain1.tld
domain1.tld A record: YOUR_WAN_IP
Checking: domain2.tld
domain2.tld A record: YOUR_WAN_IP
Checking: domain3.tld
domain3.tld A record: YOUR_WAN_IP
Checking domains for API key: API_KEY2
Checking: domain1.tld
domain1.tld A record: YOUR_WAN_IP
All finished!
