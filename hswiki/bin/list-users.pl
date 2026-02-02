#!/usr/bin/env perl
# List all users in HSWiki
# Usage: perl bin/list-users.pl

use strict;
use warnings;
use lib 'lib';
use HSWiki::DB;

print "=== HSWiki Users ===\n\n";

my $users = HSWiki::DB->fetch_all("SELECT user_id, username, email, role_id, is_active, created_at FROM users");

if (!$users || @$users == 0) {
    print "No users found.\n";
    exit 0;
}

printf "%-36s | %-20s | %-30s | %-36s | %-6s\n",
    "USER_ID", "USERNAME", "EMAIL", "ROLE_ID", "ACTIVE";
print "-" x 140 . "\n";

for my $user (@$users) {
    printf "%-36s | %-20s | %-30s | %-36s | %-6s\n",
        $user->{user_id} // 'NULL',
        $user->{username} // 'NULL',
        $user->{email} // 'NULL',
        $user->{role_id} // 'NULL',
        $user->{is_active} ? 'Yes' : 'No';
}

print "\nTotal: " . scalar(@$users) . " user(s)\n";
