#!/usr/bin/env perl
# Reset a user's password
# Usage: perl bin/reset-password.pl <username> <new_password>

use strict;
use warnings;
use lib 'lib';
use HSWiki::DB;
use HSWiki::Auth;
use HSWiki::Model::User;

my $username = shift @ARGV or die "Usage: $0 <username> <new_password>\n";
my $new_password = shift @ARGV or die "Usage: $0 <username> <new_password>\n";

# Get user
my $user = HSWiki::Model::User->find_by_username($username);
unless ($user) {
    print "User '$username' not found.\n";
    exit 1;
}

print "User found: $username (user_id: $user->{user_id})\n";

# Hash new password
my $password_hash = HSWiki::Auth->hash_password($new_password);

# Update password in main users table
HSWiki::DB->execute(
    "UPDATE users SET password_hash = ? WHERE user_id = ?",
    $password_hash, $user->{user_id}
);

# Update password in users_by_username lookup table (used for authentication)
HSWiki::DB->execute(
    "UPDATE users_by_username SET password_hash = ? WHERE username = ?",
    $password_hash, $username
);

print "Password updated successfully.\n";
print "New password: $new_password\n";
