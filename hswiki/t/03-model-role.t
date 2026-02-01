#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use lib 'lib';

# These tests require a running Cassandra instance with proper keyspace
# Skip if not available

eval { require Cassandra::Client };
if ($@) {
    plan skip_all => 'Cassandra::Client not installed';
    exit;
}

# Try to connect and access keyspace
eval {
    require HSWiki::DB;
    require HSWiki::Config;

    my $client = HSWiki::DB->client;
    my $keyspace = HSWiki::Config->get('cassandra', 'keyspace');

    # Try to use the keyspace
    $client->execute("USE $keyspace");
};
if ($@) {
    plan skip_all => 'Cassandra keyspace not available: ' . $@;
    exit;
}

plan tests => 8;

use_ok('HSWiki::Model::Role');

# Test init_defaults
ok(HSWiki::Model::Role->init_defaults, 'Default roles initialized');

# Test find_by_name
my $admin = HSWiki::Model::Role->find_by_name('admin');
ok($admin, 'Admin role found');

SKIP: {
    skip "Admin role not found", 5 unless $admin;

    is($admin->{role_name}, 'admin', 'Admin role name correct');

    my $viewer = HSWiki::Model::Role->find_by_name('viewer');
    ok($viewer, 'Viewer role found');

    # Test default_role_id
    my $default_id = HSWiki::Model::Role->default_role_id;
    ok($default_id, 'Default role ID retrieved');

    # Test admin_role_id
    my $admin_id = HSWiki::Model::Role->admin_role_id;
    ok($admin_id, 'Admin role ID retrieved');

    # Test has_permission (admin should have all)
    ok(HSWiki::Model::Role->has_permission($admin->{role_id}, 'page:write'),
       'Admin has page:write permission');
}

done_testing();
