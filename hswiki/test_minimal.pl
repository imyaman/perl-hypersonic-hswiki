#!/usr/bin/env perl
use strict;
use warnings;


use lib 'lib';
use lib '../Hypersonic-0.08/lib';
use Hypersonic;

my $server = Hypersonic->new();

# Static route - should work
$server->get('/static' => sub { 'static works' });

# Dynamic route - test if this works
$server->get('/dynamic' => sub {
    my ($req) = @_;
    return 'dynamic works';
}, { dynamic => 1 });

# Dynamic route with parse_query
$server->get('/query' => sub {
    my ($req) = @_;
    return 'query works';
}, { dynamic => 1, parse_query => 1 });

# POST dynamic
$server->post('/post' => sub {
    my ($req) = @_;
    return 'post works';
}, { dynamic => 1 });

# POST with parse_json
$server->post('/json' => sub {
    my ($req) = @_;
    return 'json works';
}, { dynamic => 1, parse_json => 1 });

$server->compile();
$server->run(port => 5208, workers => 1);
