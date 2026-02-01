#!/usr/bin/env perl
use strict;
use warnings;
use Hypersonic;
use Hypersonic::Response 'res';
my $server = Hypersonic->new();
# Static routes only - for benchmarking pure C performance
$server->get('/api/hello' => sub { my $id = 1; return res->json({ id => $id, name => "User $id" }); });
$server->get('/health'   => sub { 'OK' });
$server->compile();
$server->run(port => 5207, workers => 4);
