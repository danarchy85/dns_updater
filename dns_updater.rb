#!/usr/bin/env ruby
require 'net/http'
require 'optparse'
require 'yaml'

@usage = %Q[
Run without an argument to run DNS Updater once for configured domains.
Run with [start] to run as a daemon with a 30 minute update interval.
Run with [status|stop|restart] to manage an already running daemon.

A DreamHost Panel API Key can be created
  within your DreamHost panel at: https://panel.dreamhost.com/?tree=home.api

dns_updater.rb's first run will walk you through the initial setup:

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

]

OptionParser.new do |opts|
    opts.banner = "Usage: #{$PROGRAM_NAME} [status|start|stop]"

  opts.on('-h', '--help', 'Prints this usage info') do |val|
    puts opts, @usage
    exit
  end
end.parse!

class DNSUpdater
  def initialize(api_key)
    @api_url = "https://api.dreamhost.com/?key=#{api_key}"
  end

  def self.version
    version = '1.1.3'
  end

  # Creates a new DNS Updater config file
  def self.create_config(config_file)
    puts 'Configuration not found. Creating a new one!'
    puts 'Only A records are supported at this time.'

    config = { pidfile: '/tmp/dnsupdater.pid', log: '/tmp/dnsupdater.log', connections: {} }
    newacct = 'y'

    until newacct =~ /^n(o)?$/i
      config = add_account(config)
      print 'Do you need to add another DreamHost account/API key? (Y/N): '
      newacct = gets.chomp
    end
    
    print %Q[Final configuration:
#{config.to_yaml}

Does the above configuration look correct?: (Y/N): ]

    if gets.chomp =~ /^y(es)?$/i
      File.write(config_file, config.to_yaml)
      puts "File saved to: #{config_file}!" if File.exist?(config_file)
    else
      abort('Not writing configuration file!')
    end
  end

  def self.add_account(config)
    print 'Enter your DreamHost API Key: '
    api_key = gets.chomp
    config[:connections][api_key] = { domains: {} }

    print "\nEnter domains to manage separated by commas:
Ex: domain1.tld,domain2.tld: "
    domains = gets.chomp.split(/,/).collect(&:strip)
    format = domains.map(&:size).max

    domains.each do |dom|
      config[:connections][api_key][:domains][dom] = 'A'
      printf("%-0s %-#{format}s %0s\n", 'Added: ', dom, ' => type: A')
    end

    config
  end

  # Lists all DNS records on account
  def pull_live_records
    YAML.load(Net::HTTP.get URI "#{@api_url}&cmd=dns-list_records&format=yaml")
  end

  # Returns a hash of DNS record values
  def get_record(live_records, record, type)
    domain_record = nil
    
    live_records['data'].each do |r|
        domain_record = r if r['record'] == record && r['type'] == type
    end

    return false if domain_record == nil || domain_record.empty?
    domain_record
  end

  # Checks whether DNS record has changed
  def check_record(value, wan_ip)
    return true if value == wan_ip
    false
  end

  # Add a new record to the account
  def add_record(record, type, value)
    Net::HTTP.get URI "#{@api_url}&cmd=dns-add_record&record=#{record}&type=#{type}&value=#{value}"
  end

  # Remove a record from the account
  def remove_record(record, type, value)
    Net::HTTP.get URI "#{@api_url}&cmd=dns-remove_record&record=#{record}&type=#{type}&value=#{value}"
  end
end

class Daemon
  def initialize(config)
    @conns = config[:connections]
    @pidfile = config[:pidfile]
    @log = config[:log]
  end
  
  def status
    puts "Checking status of DNS Updater"

    unless File.exist?(@pidfile)
      puts "#{File.basename(@pidfile)} not found! DNS Updater is not running."
      return false
    end

    pid = File.read(@pidfile).to_i

    begin
      Process.getpgid(pid)
      puts "DNS Updater running as PID: #{pid}"
      return true, pid
    rescue Errno::ESRCH
      puts "DNS Updater is not running!"
      false
    end      
  end

  def run
    wan_ip = Net::HTTP.get URI 'https://api.ipify.org'

    if wan_ip !~ /^[0-9].*$/

      return [1, 'WAN IP not found!']
    end

    puts "WAN IP: #{wan_ip}"
    @conns.each_key do |api_key|
      dns = DNSUpdater.new(api_key)
      domains = @conns[api_key][:domains]
      live_records = dns.pull_live_records

      # DreamHost Rate Limiting
      if live_records['result'] == 'error'
        return [1, live_records['reason']]
      end
          
      domains.each do |record, type|
        puts "Checking: #{record}"
        domain_record = dns.get_record(live_records, record, type)
        value = domain_record == false ? false : domain_record['value']

        until dns.check_record(value, wan_ip) == true
          puts "#{record}: DNS is not current!"
          puts "Removing #{value} from #{record}"
          dns.remove_record(record, type, value)
          puts "Adding #{wan_ip} to #{record}"
          dns.add_record(record, type, wan_ip)
          sleep(2)

          live_records = dns.pull_live_records
          domain_record = dns.get_record(live_records, record, type)
          value = domain_record == false ? false : domain_record['value']
          puts "Value: #{value}"

          if value == false || value.empty?
            puts "Failed to add record for: #{record}!"
            puts " ! Skipping #{record} since it may be newly registered, or not registered at all..."
            break
          end
        end

        puts "#{record} #{type} record: #{value}"
      end
    end
  end

  def start
    state, pid = status
    return if state == true

    pid = fork do
      $stdin.reopen '/dev/null'
      $stdout.reopen '#{@log}'
      $stderr.reopen '#{@log}'
      trap(:HUP) do
        puts 'Ignoring SIGHUP'
      end
      trap(:TERM) do
        puts 'Exiting DNS Updater'
        exit
      end
      loop do
        task = run
        if task.first == 1
          puts task.last
          sleep(3660)
        else
          sleep(900)
        end
      end

      puts 'DNS Updater Exiting.'
    end

    puts "Writing #{pid} to #{@pidfile}"
    File.write(@pidfile, pid)
    puts "DNSUpdater is running as PID: #{pid}"
    Process.detach(pid)
  end

  def stop
    state, pid = status

    if state == true
      puts "Stopping DNS Updater, PID: #{pid}."
      Process.kill('TERM', pid)

      File.delete(@pidfile)
      status
    end
  end

  def restart
    state, pid = status
    attempt = 1

    until state == false || attempt == 3
      puts "DNS Updater is running as PID: #{pid}"
      puts 'Stopping DNS Updater...'
      stop
      attempt =+ 1
      sleep(3)
      state, pid = status
    end

    if state == false
      puts 'DNS Updater is not running.'
      start
    else
      puts "ERROR: Could not stop DNS Updater PID: #{pid}"
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  config_file = File.join(ENV['HOME'], '/.DH_DNS_Config')
  DNSUpdater.create_config(config_file) unless File.exist?(config_file)

  config = YAML.load_file(config_file)
  daemon = Daemon.new(config)

  if ARGV.empty?
  # unless %w(status start stop restart).include?(ARGV.first)
    puts 'No action provided! Running once to update all domains!'
    daemon.run
    puts 'All finished!'
    exit
  end

  case ARGV.first
  when 'status'
    daemon.status
  when 'start'
    daemon.start
  when 'stop'
    daemon.stop
  when 'restart'
    daemon.restart
  else
    puts "ERROR: Invalid argument provided: #{ARGV.first}"
    abort(@usage.lines[0..3].join)
  end
end
