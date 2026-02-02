#!/usr/bin/env perl
# List all roles in HSWiki
# Usage: perl bin/list-roles.pl

use strict;
use warnings;
use lib 'lib';
use HSWiki::DB;

print "=== HSWiki Roles ===\n\n";

my $roles = HSWiki::DB->fetch_all("SELECT role_id, role_name, permissions, description FROM roles");

if (!$roles || @$roles == 0) {
    print "No roles found.\n";
    exit 0;
}

printf "%-36s | %-15s | %-50s\n",
    "ROLE_ID", "ROLE_NAME", "PERMISSIONS";
print "-" x 110 . "\n";

for my $role (@$roles) {
    my $perms = $role->{permissions};
    my $perm_str = ref($perms) eq 'ARRAY' ? join(', ', @$perms) : ($perms // 'NULL');
    printf "%-36s | %-15s | %-50s\n",
        $role->{role_id} // 'NULL',
        $role->{role_name} // 'NULL',
        substr($perm_str, 0, 50);
}

print "\nTotal: " . scalar(@$roles) . " role(s)\n";
