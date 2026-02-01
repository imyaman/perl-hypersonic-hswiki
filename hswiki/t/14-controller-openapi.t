#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use lib 'lib';

# Load modules
use_ok('HSWiki::Controller::OpenAPI');

# Test that controller can be loaded
can_ok('HSWiki::Controller::OpenAPI', 'register');
can_ok('HSWiki::Controller::OpenAPI', 'list_spaces');
can_ok('HSWiki::Controller::OpenAPI', 'get_space');
can_ok('HSWiki::Controller::OpenAPI', 'list_pages');
can_ok('HSWiki::Controller::OpenAPI', 'get_page');
can_ok('HSWiki::Controller::OpenAPI', 'render_markup');
can_ok('HSWiki::Controller::OpenAPI', 'search');

done_testing();
