#!/usr/bin/env perl
use strict;
use warnings;


use lib 'lib';
use Hypersonic;
use Hypersonic::Response qw(res);

my $server = Hypersonic->new();

# Manual before middleware that logs
$server->before(sub {
    my ($req) = @_;
    warn "BEFORE: got request\n";
    return;  # Continue to handler
});

# Manual after middleware that logs
$server->after(sub {
    my ($req, $res) = @_;
    warn "AFTER: req=" . (defined $req ? 'defined' : 'undef') . " res=" . (defined $res ? 'defined' : 'undef') . "\n";
    if (defined $res) {
        warn "AFTER: res type=" . ref($res) . "\n";
    }
    return $res;
});

$server->get('/health' => sub { 'OK' });

$server->get('/api/test' => sub {
    my ($req) = @_;
    warn "HANDLER: running\n";
    return res->json({ test => 'ok' });
}, { dynamic => 1 });

$server->compile();
$server->run(port => 5213, workers => 1);
