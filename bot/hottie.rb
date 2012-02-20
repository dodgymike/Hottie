require 'rubygems'
require 'net/yail'
require 'net/yail/irc_bot'
require "dbi"

class Hottie < Net::YAIL::IRCBot
  attr_accessor :dbh

  def initialize(config, *args)
    super(config, *args)
    # connect to the MySQL server
    @dbh = DBI.connect("DBI:Pg:hottie:localhost", "hottie", "hottieisamonkey")
    @channels = {}
  end

  def add_custom_handlers
    @irc.prepend_handler :irc_loop, method(:fetch_alerts)
    @irc.prepend_handler :outgoing_begin_connection, method(:reset_three)
    @irc.prepend_handler :incoming_numeric_401, method(:reset_two)
    @irc.prepend_handler :incoming_error, method(:reset_one)
  end

  def reset_one(a)
    reset_two(a,"")
  end

  def reset_two(a,b)
    reset_three(a,b,"")
  end

  def reset_three(a, b, c)
    puts "a (#{a}) b (#{b}) c (#{c})"
    @channels.each_key do |channel|
      begin
        @irc.part(destination)
      rescue Exception => e
      end
    end

    @channels.clear
  end

  def fetch_alerts
    begin
      # Select all rows from simple01
      sth = dbh.prepare('select id, source, destination, message from hottie_alerts where sent = false')
      sth.execute

      # Print out each row
      while row=sth.fetch do
        id = row[0]
        source = row[1]
        destination = row[2]
        message = row[3]

        puts "GOT NEW ALERT id (#{id}) source (#{source}) destination (#{destination}) message (#{message})"

        if destination =~ /^\#/ && @channels[destination].nil?
          @channels[destination] = true
          @irc.join(destination)
        end

        #puts @channels[destination]

        msg(destination, message)

        dbh.do("update hottie_alerts set sent = true where id = #{id}")
      end

    rescue Exception => e
      puts "An error occurred"
      puts "Error code: #{e.err}"
      puts "Error message: #{e.errstr}"
    end
  end
end

irc = Hottie.new(
  :address    => 'irc.ctwug.za.net', # "irc.atrum.org", #
  :username   => 'Hottie',
  :realname   => 'Hottie McBottie',
  :nicknames  => ['hottie']
)

irc.connect_socket


# create table hottie_alerts (id serial, alert_time timestamp not null default CURRENT_TIMESTAMP, source text, destination text, message text, sent boolean default false);


#irc.handle(:irc_loop) do |e|
#  $stderr.puts "irc loop"
#end

#irc.on_irc_loop do |e|
#  $stderr.puts "irc loop"
#end

#irc.set_callback(:irc_loop) do |event|
#  $stderr.puts "irc loop"
#end

#irc.set_callback(:incoming_any) do |event|
#  $stderr.puts "incoming any"
#end

# Loops forever here until CTRL+C is hit.
irc.start_listening
irc.irc_loop


