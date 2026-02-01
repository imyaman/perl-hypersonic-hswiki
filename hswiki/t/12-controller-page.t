#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use lib 'lib';

# Load modules
use_ok('HSWiki::Controller::Page');

# Test that controller can be loaded
can_ok('HSWiki::Controller::Page', 'register');
can_ok('HSWiki::Controller::Page', 'list');
can_ok('HSWiki::Controller::Page', 'create');
can_ok('HSWiki::Controller::Page', 'get');
can_ok('HSWiki::Controller::Page', 'update');
can_ok('HSWiki::Controller::Page', 'delete');
can_ok('HSWiki::Controller::Page', 'versions');
can_ok('HSWiki::Controller::Page', 'get_version');
can_ok('HSWiki::Controller::Page', 'restore');

done_testing();
