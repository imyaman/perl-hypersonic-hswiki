#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use lib 'lib';

# Load modules
use_ok('HSWiki::Controller::Auth');

# Test that controller can be loaded
can_ok('HSWiki::Controller::Auth', 'register');
can_ok('HSWiki::Controller::Auth', 'register_user');
can_ok('HSWiki::Controller::Auth', 'login');
can_ok('HSWiki::Controller::Auth', 'logout');
can_ok('HSWiki::Controller::Auth', 'me');
can_ok('HSWiki::Controller::Auth', 'change_password');

done_testing();
