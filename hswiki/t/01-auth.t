#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 14;

use lib 'lib';

use_ok('HSWiki::Auth');

# Test token generation
my $token = HSWiki::Auth->generate_token(32);
ok($token, 'Token generated');
ok(length($token) >= 32, 'Token has sufficient length');

my $token2 = HSWiki::Auth->generate_token(32);
isnt($token, $token2, 'Tokens are unique');

# Test API key generation
my $api_key = HSWiki::Auth->generate_api_key;
ok($api_key, 'API key generated');
ok(length($api_key) >= 32, 'API key has sufficient length');

# Test password hashing
my $password = 'test_password_123';
my $hash = HSWiki::Auth->hash_password($password);
ok($hash, 'Password hash generated');
ok($hash ne $password, 'Hash is different from password');

# Test password verification
ok(HSWiki::Auth->verify_password($password, $hash), 'Correct password verifies');
ok(!HSWiki::Auth->verify_password('wrong_password', $hash), 'Wrong password fails');

# Test password validation
my $errors = HSWiki::Auth->validate_password('short');
ok($errors, 'Short password fails validation');
is(ref($errors), 'ARRAY', 'Errors returned as array');

my $ok_errors = HSWiki::Auth->validate_password('validpassword123');
ok(!$ok_errors, 'Valid password passes');

# Test username validation
my $username_error = HSWiki::Auth->validate_username('ab');
ok($username_error, 'Short username fails');

done_testing();
