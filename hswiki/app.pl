#!/usr/bin/env perl
use strict;
use warnings;

use lib 'lib';
use Hypersonic;
use Hypersonic::Response qw(res);

use HSWiki::Config;
use HSWiki::DB;
use HSWiki::Auth;
use HSWiki::Controller::Auth;
use HSWiki::Controller::Space;
use HSWiki::Controller::Page;
use HSWiki::Controller::Admin;
use HSWiki::Controller::OpenAPI;
use HSWiki::Middleware::Auth;
use HSWiki::Middleware::RBAC;

# Create server instance
my $server = Hypersonic->new();

# NOTE: session_config disabled due to Hypersonic bug where after_middleware
# doesn't receive $res parameter, causing $res->cookie() to fail.
# TODO: Re-enable when Hypersonic is fixed or implement custom session handling.
# my $session_config = HSWiki::Config->session;
# $server->session_config(
#     secret      => $session_config->{secret},
#     cookie_name => $session_config->{cookie_name},
#     max_age     => $session_config->{max_age},
#     httponly    => $session_config->{httponly},
#     secure      => $session_config->{secure},
#     samesite    => $session_config->{samesite},
# );

# ===========================================
# Health check endpoint
# ===========================================
$server->get('/health' => sub { 'OK' });

$server->get('/api/hello' => sub { '{"message":"Hello, HSWiki!"}' });

# Simple test route returning Response object (required when sessions enabled)
$server->post('/api/test-plain' => sub {
    my ($req) = @_;
    return res->json({ test => 'plain' });
}, { dynamic => 1 });

# Test with hashref - also needs Response object
$server->post('/api/test-hash' => sub {
    my ($req) = @_;
    return res->json({ test => 'hash' });
}, { dynamic => 1 });

# ===========================================
# Authentication routes (/api/auth)
# ===========================================
HSWiki::Controller::Auth->register($server);

# ===========================================
# Routes - avoiding prefix collision by using distinct paths
# Page routes use /api/pages/:space_key/... to avoid collision with /api/spaces/:key
# ===========================================

# /api/render (separate path, no conflict)
$server->post('/api/render' => sub {
    HSWiki::Controller::Page->render_preview(@_);
}, { dynamic => 1, parse_json => 1 });

# ===== SPACE ROUTES =====
# /api/spaces - list spaces (static path)
$server->get('/api/spaces' => HSWiki::Middleware::Auth->wrap(sub {
    HSWiki::Controller::Space->list(@_);
}, optional => 1), { dynamic => 1 });

$server->post('/api/spaces' => HSWiki::Middleware::Auth->wrap(sub {
    HSWiki::Controller::Space->create(@_);
}), { dynamic => 1, parse_json => 1 });

# /api/spaces/:key - get/update/delete space
$server->get('/api/spaces/:key' => HSWiki::Middleware::Auth->wrap(sub {
    HSWiki::Controller::Space->get(@_);
}, optional => 1), { dynamic => 1 });

$server->put('/api/spaces/:key' => HSWiki::Middleware::Auth->wrap(sub {
    HSWiki::Controller::Space->update(@_);
}), { dynamic => 1, parse_json => 1 });

$server->del('/api/spaces/:key' => HSWiki::Middleware::Auth->wrap(sub {
    HSWiki::Controller::Space->delete(@_);
}), { dynamic => 1 });

# /api/spaces/:key/permissions
$server->get('/api/spaces/:key/permissions' => HSWiki::Middleware::Auth->wrap(sub {
    HSWiki::Controller::Space->list_permissions(@_);
}), { dynamic => 1 });

$server->post('/api/spaces/:key/permissions' => HSWiki::Middleware::Auth->wrap(sub {
    HSWiki::Controller::Space->grant_permission(@_);
}), { dynamic => 1, parse_json => 1 });

$server->del('/api/spaces/:key/permissions/:user_id' => HSWiki::Middleware::Auth->wrap(sub {
    HSWiki::Controller::Space->revoke_permission(@_);
}), { dynamic => 1 });

# ===== PAGE ROUTES - Using literal segments to avoid Hypersonic routing issues =====
# Each route has unique literal prefix: /list/, /view/, /edit/, /versions/, /restore/

# GET /api/pages/list/:space_key - list pages in space
$server->get('/api/pages/list/:space_key' => HSWiki::Middleware::Auth->wrap(sub {
    HSWiki::Controller::Page->list(@_);
}, optional => 1), { dynamic => 1 });

# POST /api/pages/create/:space_key - create page
$server->post('/api/pages/create/:space_key' => HSWiki::Middleware::Auth->wrap(sub {
    HSWiki::Controller::Page->create(@_);
}), { dynamic => 1, parse_json => 1 });

# GET /api/pages/view/:space_key/:slug - get single page
$server->get('/api/pages/view/:space_key/:slug' => HSWiki::Middleware::Auth->wrap(sub {
    HSWiki::Controller::Page->get(@_);
}, optional => 1), { dynamic => 1 });

# PUT /api/pages/edit/:space_key/:slug - update page
$server->put('/api/pages/edit/:space_key/:slug' => HSWiki::Middleware::Auth->wrap(sub {
    HSWiki::Controller::Page->update(@_);
}), { dynamic => 1, parse_json => 1 });

# DELETE /api/pages/delete/:space_key/:slug - delete page
$server->del('/api/pages/delete/:space_key/:slug' => HSWiki::Middleware::Auth->wrap(sub {
    HSWiki::Controller::Page->delete(@_);
}), { dynamic => 1 });

# GET /api/pages/versions/:space_key/:slug - get version history
$server->get('/api/pages/versions/:space_key/:slug' => HSWiki::Middleware::Auth->wrap(sub {
    HSWiki::Controller::Page->versions(@_);
}, optional => 1), { dynamic => 1 });

# GET /api/pages/version/:space_key/:slug/:version - get specific version
$server->get('/api/pages/version/:space_key/:slug/:version' => HSWiki::Middleware::Auth->wrap(sub {
    HSWiki::Controller::Page->get_version(@_);
}, optional => 1), { dynamic => 1 });

# POST /api/pages/restore/:space_key/:slug - restore to version
$server->post('/api/pages/restore/:space_key/:slug' => HSWiki::Middleware::Auth->wrap(sub {
    HSWiki::Controller::Page->restore(@_);
}), { dynamic => 1, parse_json => 1 });

# ===========================================
# Admin routes (/api/admin)
# ===========================================
HSWiki::Controller::Admin->register($server);

# ===========================================
# OpenAPI routes (/openapi)
# ===========================================
HSWiki::Controller::OpenAPI->register($server);

# Compile and run
$server->compile();

my $server_config = HSWiki::Config->server;
$server->run(
    port    => $server_config->{port},
    workers => $server_config->{workers},
);
