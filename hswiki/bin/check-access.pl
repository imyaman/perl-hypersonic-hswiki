#!/usr/bin/env perl
# Check if a user can access a space
# Usage: perl bin/check-access.pl <username> <space_key>

use strict;
use warnings;
use lib 'lib';
use HSWiki::DB;
use HSWiki::Model::Space;
use HSWiki::Model::User;

my $username = shift @ARGV or die "Usage: $0 <username> <space_key>\n";
my $space_key = shift @ARGV or die "Usage: $0 <username> <space_key>\n";

# Get user
my $user = HSWiki::Model::User->find_by_username($username);
unless ($user) {
    print "User '$username' not found.\n";
    exit 1;
}
print "User: $username (user_id: $user->{user_id})\n";

# Get space
my $space = HSWiki::Model::Space->find_by_key($space_key);
unless ($space) {
    print "Space '$space_key' not found.\n";
    exit 1;
}
print "Space: $space_key (space_id: $space->{space_id})\n";
print "  is_public: " . ($space->{is_public} ? "Yes" : "No") . "\n";
print "  owner_id: " . ($space->{owner_id} // "NULL") . "\n";

# Check access
print "\n=== Access Check ===\n";

# 1. Is public?
if ($space->{is_public}) {
    print "✓ Space is public - anyone can access\n";
}

# 2. Is owner?
if ($space->{owner_id} && $space->{owner_id} eq $user->{user_id}) {
    print "✓ User is the OWNER of this space\n";
} else {
    print "✗ User is NOT the owner\n";
}

# 3. Has permission?
my $permission = HSWiki::Model::Space->get_permission($space->{space_id}, $user->{user_id});
if ($permission) {
    print "✓ User has permission: $permission\n";
} else {
    print "✗ User has NO permission entry in space_permissions\n";
}

# Final result
my $can_access = HSWiki::Model::Space->can_access($space->{space_id}, $user->{user_id});
my $can_write = HSWiki::Model::Space->can_write($space->{space_id}, $user->{user_id});
my $is_admin = HSWiki::Model::Space->is_admin($space->{space_id}, $user->{user_id});

print "\n=== Result ===\n";
print "can_access: " . ($can_access ? "YES" : "NO") . "\n";
print "can_write:  " . ($can_write ? "YES" : "NO") . "\n";
print "is_admin:   " . ($is_admin ? "YES" : "NO") . "\n";
