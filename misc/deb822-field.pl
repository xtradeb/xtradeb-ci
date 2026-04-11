#!/usr/bin/perl -T
# deb822-field.pl
#
# Convenience script to extract field values from deb822(5)-formatted files
#
# Usage: deb822-field FIELD_NAME [INPUT_FILE] ...
#
#   --comma-sep          Split the field value on commas and output
#                        one item per line
#   --space-sep          Split the field value on whitespace and output
#                        one item per line
#   --validate-regex=RE  Regular expression to validate value(s); do not
#                        include start/end anchors as these are implied
#
# Example: deb822-field Build-Depends debian/control
#

use strict;
use warnings;

use Getopt::Long;

my $sep;
my $validate_regex;

GetOptions(
	"comma-sep" => sub { $sep = "comma" },
	"space-sep" => sub { $sep = "space" },
	"validate-regex=s" => \$validate_regex
);

my $field = $ARGV[0];
shift(@ARGV);

die "Error: Field name must not include the trailing colon\n"
	if $field =~ /:$/;

local $/;

while (<>)
{
	if (/^$field:(.*(?:\n[\t ]+\S.*)*)/m)
	{
		my $value = $1;
		$value =~ s/\n/ /g;
		$value =~ s/[\t ]+/ /g;
		$value =~ s/^ +| +$//g;

		if ($sep eq "comma")
		{
			$value =~ s/,$//;
			$value =~ s/, */\n/g;
		}
		elsif ($sep eq "space")
		{
			$value =~ s/ +/\n/g;
		}

		if ($validate_regex)
		{
			my @value_list = split(/\n/, $value);
			my @bad = grep(!/^$validate_regex$/, @value_list);
			die "Error: Requested field has invalid value(s)\n"
				if @bad;
		}

		print "$value\n";
	}
}

# end deb822-field.pl
