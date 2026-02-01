#!/usr/bin/env perl
use strict;
use warnings;


use lib 'lib';
use Hypersonic;
use Hypersonic::Response qw(res);

my $server = Hypersonic->new();

# No session config

$server->get('/health' => sub { 'OK' });

$server->post('/api/test' => sub {
    my ($req) = @_;
    return '{"test":"ok"}';
}, { dynamic => 1 });

$server->compile();
$server->run(port => 5210, workers => 1);
