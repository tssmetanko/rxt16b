#!/usr/bin/perl
use Sys::Syslog qw( :DEFAULT setlogsock );
#use strict;
use Getopt::Std;

my %options=();
getopts("t:p:", \%options);

my $syslog_tag="logger";
my $syslog_priority="notice";
$syslog_tag="$options{t}" if defined $options{t};
$syslog_facility="$options{p}" if defined $options{p};

sub usage {
	my $command = $0;
	$command =~ s#^.*/##;
	print STDERR (
	"usage: $command -p [priority: by default notyce] -t [syslog name or tag]\n".
	"       ...\n"
	);
}

setlogsock('unix');
openlog($syslog_tag,'cons','pid','local0');

if ( STDIN and not @ARGV ){
	while ($log=<STDIN>) {
        	syslog($syslog_priority, $log); 
	}
}elsif( @ARGV ){
	syslog($syslog_priority,"@ARGV");
}else{
	usage();
}

