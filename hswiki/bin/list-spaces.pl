#!/usr/bin/env perl
# List all spaces in HSWiki
# Usage: perl bin/list-spaces.pl

use strict;
use warnings;
use lib 'lib';
use HSWiki::DB;

print "=== HSWiki Spaces ===\n\n";

my $spaces = HSWiki::DB->fetch_all("SELECT space_id, space_key, name, is_public, owner_id, created_at FROM spaces");

if (!$spaces || @$spaces == 0) {
    print "No spaces found.\n";
    exit 0;
}

printf "%-36s | %-20s | %-25s | %-6s | %-36s\n",
    "SPACE_ID", "SPACE_KEY", "NAME", "PUBLIC", "OWNER_ID";
print "-" x 140 . "\n";

for my $space (@$spaces) {
    printf "%-36s | %-20s | %-25s | %-6s | %-36s\n",
        $space->{space_id} // 'NULL',
        $space->{space_key} // 'NULL',
        substr($space->{name} // 'NULL', 0, 25),
        $space->{is_public} ? 'Yes' : 'No',
        $space->{owner_id} // 'NULL';
}

print "\nTotal: " . scalar(@$spaces) . " space(s)\n";
