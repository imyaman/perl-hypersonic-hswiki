#!/usr/bin/env perl
use strict;
use warnings;
use Test::More tests => 12;

use lib 'lib';

use_ok('HSWiki::Config');

# Test config retrieval
my $config = HSWiki::Config->config;
ok($config, 'Config loaded');
isa_ok($config, 'HASH', 'Config is a hash');

# Test Cassandra config
my $cass = HSWiki::Config->cassandra;
ok($cass, 'Cassandra config exists');
ok($cass->{contact_points}, 'Contact points defined');
is(ref($cass->{contact_points}), 'ARRAY', 'Contact points is array');
ok($cass->{keyspace}, 'Keyspace defined');

# Test session config
my $session = HSWiki::Config->session;
ok($session, 'Session config exists');
ok($session->{secret}, 'Session secret defined');
ok(length($session->{secret}) >= 16, 'Session secret is at least 16 chars');

# Test server config
my $server = HSWiki::Config->server;
ok($server, 'Server config exists');
is($server->{port}, 5207, 'Default port is 5207');

done_testing();
