#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use lib 'lib';

# Load modules
use_ok('HSWiki::Controller::Admin');

# Test that controller can be loaded
can_ok('HSWiki::Controller::Admin', 'register');
can_ok('HSWiki::Controller::Admin', 'list_users');
can_ok('HSWiki::Controller::Admin', 'get_user');
can_ok('HSWiki::Controller::Admin', 'update_user');
can_ok('HSWiki::Controller::Admin', 'deactivate_user');
can_ok('HSWiki::Controller::Admin', 'list_roles');
can_ok('HSWiki::Controller::Admin', 'create_role');

done_testing();
