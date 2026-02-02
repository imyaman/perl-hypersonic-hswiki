package HSWiki::Session;

use strict;
use warnings;

use Digest::SHA qw(sha256_hex hmac_sha256_hex);
use MIME::Base64 qw(encode_base64url decode_base64url);
use Cpanel::JSON::XS qw(encode_json decode_json);
use HSWiki::Config;

our $VERSION = '0.02';

# Redis connection
my $REDIS;

# Session secret from config
my $SECRET;

sub _get_secret {
    $SECRET //= HSWiki::Config->session->{secret};
    return $SECRET;
}

# Get Redis connection
sub _redis {
    my ($class) = @_;

    unless ($REDIS) {
        require Redis;
        my $config = HSWiki::Config->redis;
        $REDIS = Redis->new(
            server    => $config->{server},
            reconnect => 60,
            every     => 1000,
        );
    }

    return $REDIS;
}

# Session key prefix
sub _session_key {
    my ($class, $session_id) = @_;
    return "hswiki:session:$session_id";
}

# Generate a session ID
sub generate_id {
    my ($class) = @_;

    my $bytes;
    if (-r '/dev/urandom') {
        open my $fh, '<:raw', '/dev/urandom' or die "Cannot open /dev/urandom: $!";
        read($fh, $bytes, 16);
        close $fh;
    } else {
        $bytes = pack('C*', map { int(rand(256)) } 1..16);
    }

    return unpack('H*', $bytes);
}

# Sign a session ID
sub sign {
    my ($class, $session_id) = @_;
    my $sig = substr(hmac_sha256_hex($session_id, $class->_get_secret), 0, 16);
    return "$session_id.$sig";
}

# Verify and extract session ID from signed cookie
sub verify {
    my ($class, $signed_cookie) = @_;

    return unless $signed_cookie && $signed_cookie =~ /^([a-f0-9]{32})\.([a-f0-9]{16})$/;

    my ($session_id, $sig) = ($1, $2);
    my $expected = substr(hmac_sha256_hex($session_id, $class->_get_secret), 0, 16);

    # Constant-time comparison
    return unless length($sig) == length($expected);
    my $diff = 0;
    $diff |= ord(substr($sig, $_, 1)) ^ ord(substr($expected, $_, 1)) for 0 .. length($sig) - 1;

    return $diff == 0 ? $session_id : undef;
}

# Get session data for a request
sub get {
    my ($class, $req) = @_;

    # Check for session cookie
    my $config = HSWiki::Config->session;
    my $signed_cookie = $req->cookie($config->{cookie_name});

    if ($signed_cookie) {
        my $session_id = $class->verify($signed_cookie);
        if ($session_id) {
            my $redis = $class->_redis;
            my $json = $redis->get($class->_session_key($session_id));
            if ($json) {
                my $data = eval { decode_json($json) } || {};
                return ($session_id, $data);
            }
        }
    }

    return (undef, {});
}

# Get or create session
sub get_or_create {
    my ($class, $req) = @_;

    my ($session_id, $data) = $class->get($req);

    unless ($session_id) {
        $session_id = $class->generate_id;
        $data = { _created => time() };
        $class->_save($session_id, $data);
    }

    return ($session_id, $data);
}

# Save session data to Redis
sub _save {
    my ($class, $session_id, $data) = @_;

    my $config = HSWiki::Config->session;
    my $ttl = $config->{max_age} || 86400;
    my $redis = $class->_redis;

    $redis->setex(
        $class->_session_key($session_id),
        $ttl,
        encode_json($data)
    );
}

# Set session data
sub set {
    my ($class, $session_id, $key, $value) = @_;

    my $redis = $class->_redis;
    my $session_key = $class->_session_key($session_id);

    # Get current data
    my $json = $redis->get($session_key);
    my $data = $json ? (eval { decode_json($json) } || {}) : {};

    # Update and save
    $data->{$key} = $value;
    $class->_save($session_id, $data);
}

# Get session value
sub get_value {
    my ($class, $session_id, $key) = @_;

    return unless $session_id;

    my $redis = $class->_redis;
    my $json = $redis->get($class->_session_key($session_id));
    return unless $json;

    my $data = eval { decode_json($json) } || {};
    return $data->{$key};
}

# Clear session
sub clear {
    my ($class, $session_id) = @_;

    return unless $session_id;

    my $redis = $class->_redis;
    $redis->del($class->_session_key($session_id));
}

# Add session cookie to response
sub set_cookie {
    my ($class, $res, $session_id) = @_;

    my $config = HSWiki::Config->session;
    my $signed = $class->sign($session_id);

    $res->cookie($config->{cookie_name}, $signed,
        path     => '/',
        max_age  => $config->{max_age},
        httponly => $config->{httponly},
        secure   => $config->{secure},
        samesite => $config->{samesite},
    );
}

# Clear session cookie from response
sub clear_cookie {
    my ($class, $res) = @_;

    my $config = HSWiki::Config->session;
    $res->cookie($config->{cookie_name}, '',
        path    => '/',
        max_age => 0,
    );
}

1;

__END__

=head1 NAME

HSWiki::Session - Redis-based session management for HSWiki

=head1 DESCRIPTION

This module provides session management using Redis (or Valkey) as the
backend storage. Sessions are shared across all Hypersonic workers.

=head1 USAGE

    use HSWiki::Session;

    # In a handler
    sub my_handler {
        my ($req) = @_;

        # Get or create session
        my ($session_id, $data) = HSWiki::Session->get_or_create($req);

        # Set session values
        HSWiki::Session->set($session_id, 'user_id', 123);

        # Get session values
        my $user_id = HSWiki::Session->get_value($session_id, 'user_id');

        # Build response and add session cookie
        my $res = res->json({ success => 1 });
        HSWiki::Session->set_cookie($res, $session_id);

        return $res;
    }

=head1 REDIS KEYS

Sessions are stored with the key pattern: C<hswiki:session:{session_id}>

=cut
