#!/usr/bin/env perl
# List space permissions in HSWiki
# Usage: perl bin/list-permissions.pl [space_key]

use strict;
use warnings;
use lib 'lib';
use HSWiki::DB;

my $space_key = shift @ARGV;

print "=== HSWiki Space Permissions ===\n\n";

my $perms;
if ($space_key) {
    # Get space_id first
    my $space = HSWiki::DB->fetch_one(
        "SELECT space_id FROM spaces_by_key WHERE space_key = ?",
        $space_key
    );

    unless ($space) {
        print "Space '$space_key' not found.\n";
        exit 1;
    }

    $perms = HSWiki::DB->fetch_all(
        "SELECT space_id, user_id, permission, granted_at FROM space_permissions WHERE space_id = ?",
        $space->{space_id}
    );
    print "Permissions for space: $space_key\n\n";
} else {
    $perms = HSWiki::DB->fetch_all("SELECT space_id, user_id, permission, granted_at FROM space_permissions");
    print "All space permissions:\n\n";
}

if (!$perms || @$perms == 0) {
    print "No permissions found.\n";
    exit 0;
}

printf "%-36s | %-36s | %-10s | %-20s\n",
    "SPACE_ID", "USER_ID", "PERMISSION", "GRANTED_AT";
print "-" x 120 . "\n";

for my $perm (@$perms) {
    my $granted = $perm->{granted_at} ? scalar(localtime($perm->{granted_at}/1000)) : 'NULL';
    printf "%-36s | %-36s | %-10s | %-20s\n",
        $perm->{space_id} // 'NULL',
        $perm->{user_id} // 'NULL',
        $perm->{permission} // 'NULL',
        $granted;
}

print "\nTotal: " . scalar(@$perms) . " permission(s)\n";
