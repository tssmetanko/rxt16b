#!/usr/bin/env ruby

# == Synopsis
#
# logger. This ruby implements of logger program. This implementation have not limit 1Kb per event.
#
# == Usage
#
# logger [OPTION] ... EVENT
#
# -h, --help:
#    show help
# -v, --verbose
#    show current log possition
# -t --tag [name of event]:
#   set program name of syslog enevnt
# -f --facility [level number]
#   set facility level of syslog event
# EVENT: The event which should be send to syslog.

require 'syslog'
require 'getoptlong'
require 'rdoc/usage'
require 'fcntl'

tag=nil
priority=nil
facility=16
verbose=nil

options=GetoptLong.new(
	['--help','-h', GetoptLong::NO_ARGUMENT],
	['--tag','-t', GetoptLong::OPTIONAL_ARGUMENT],
	['--facility','-f', GetoptLong::OPTIONAL_ARGUMENT],
	['--verbose','-v', GetoptLong::NO_ARGUMENT]
)

options.each do |opt, arg|
	case opt
		when '--help'
			RDoc::usage
		when '--tag'
			tag = arg
		when '--facility'
			facility = arg
			#Print usage and exit immediatelly when facility is not number
			RDoc::usage if facility.to_i.to_s!=facility
		when '--verbose'
			verbose = true
	end
end

#puts "#{verbose}"
#exit

logger=Syslog.open(tag,Syslog::LOG_NDELAY,facility.to_i)

until ARGV.empty? do
  #puts "From arguments: #{ARGV.shift}";
  logger.info("#{ARGV.shift}")
end
if STDIN.fcntl(Fcntl::F_GETFL, 0) == 0
	position = 0
	while event = gets
		logger.info("#{event}")
		if verbose
			print 13.chr
			print "Current position: #{position}"
			position += 1
		end
	end
end

