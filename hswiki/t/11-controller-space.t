#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use lib 'lib';

# Load modules
use_ok('HSWiki::Controller::Space');

# Test that controller can be loaded
can_ok('HSWiki::Controller::Space', 'register');
can_ok('HSWiki::Controller::Space', 'list');
can_ok('HSWiki::Controller::Space', 'create');
can_ok('HSWiki::Controller::Space', 'get');
can_ok('HSWiki::Controller::Space', 'update');
can_ok('HSWiki::Controller::Space', 'delete');
can_ok('HSWiki::Controller::Space', 'grant_permission');
can_ok('HSWiki::Controller::Space', 'revoke_permission');

done_testing();
