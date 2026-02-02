#!/usr/bin/env perl
# Simple CQL query tool for HSWiki
# Usage: perl bin/cql-query.pl "SELECT * FROM users"

use strict;
use warnings;
use lib 'lib';
use HSWiki::DB;
use Data::Dumper;

my $query = shift @ARGV or die "Usage: $0 'CQL QUERY'\n";

print "Executing: $query\n\n";

my $rows = HSWiki::DB->fetch_all($query);

if (!$rows || @$rows == 0) {
    print "No results.\n";
    exit 0;
}

# Print column headers
my @cols = sort keys %{$rows->[0]};
print join("\t| ", @cols) . "\n";
print "-" x (length(join("\t| ", @cols)) + 10) . "\n";

# Print rows
for my $row (@$rows) {
    my @vals = map { defined $row->{$_} ? $row->{$_} : 'NULL' } @cols;
    print join("\t| ", @vals) . "\n";
}

print "\n" . scalar(@$rows) . " row(s) returned.\n";
