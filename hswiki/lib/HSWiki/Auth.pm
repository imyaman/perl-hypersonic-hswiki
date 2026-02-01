package HSWiki::Auth;

use strict;
use warnings;


use Digest::SHA qw(sha256_hex hmac_sha256_hex);
use MIME::Base64 qw(encode_base64url decode_base64url);
use HSWiki::Config;
use HSWiki::Session;

our $VERSION = '0.01';

# Try to load Crypt::Argon2 for better password hashing
my $HAS_ARGON2;
BEGIN {
    eval { require Crypt::Argon2 };
    $HAS_ARGON2 = !$@;
    if ($HAS_ARGON2) {
        Crypt::Argon2->import(qw(argon2id_pass argon2id_verify));
    }
}

# Generate a secure random string
sub generate_token {
    my ($class, $length) = @_;
    $length //= 32;

    my $bytes = '';
    if (-r '/dev/urandom') {
        open my $fh, '<:raw', '/dev/urandom' or die "Cannot open /dev/urandom: $!";
        read($fh, $bytes, $length);
        close $fh;
    } else {
        # Fallback (less secure)
        $bytes = pack('C*', map { int(rand(256)) } 1..$length);
    }

    return encode_base64url($bytes, '');
}

# Generate API key
sub generate_api_key {
    my ($class) = @_;
    my $length = HSWiki::Config->get('security', 'api_key_length') // 32;
    return $class->generate_token($length);
}

# Hash a password
sub hash_password {
    my ($class, $password) = @_;

    if ($HAS_ARGON2) {
        # Use Argon2id (recommended for password hashing)
        my $salt = $class->generate_token(16);
        return argon2id_pass($password, $salt, 3, '65536k', 4, 32);
    }

    # Fallback: Use SHA-256 with salt and iterations (PBKDF2-like)
    my $salt = $class->generate_token(16);
    my $iterations = 100000;

    my $hash = $password . $salt;
    for (1..$iterations) {
        $hash = sha256_hex($hash . $salt . $password);
    }

    # Format: $sha256$iterations$salt$hash
    return sprintf('$sha256$%d$%s$%s', $iterations, $salt, $hash);
}

# Verify a password against a hash
sub verify_password {
    my ($class, $password, $hash) = @_;

    return 0 unless $password && $hash;

    # Check if it's an Argon2 hash
    if ($hash =~ /^\$argon2/) {
        if ($HAS_ARGON2) {
            eval { return argon2id_verify($hash, $password) };
            return 0 if $@;
        }
        warn "Argon2 hash found but Crypt::Argon2 not available";
        return 0;
    }

    # SHA-256 fallback format: $sha256$iterations$salt$hash
    if ($hash =~ /^\$sha256\$(\d+)\$([^\$]+)\$([a-f0-9]+)$/) {
        my ($iterations, $salt, $stored_hash) = ($1, $2, $3);

        my $computed = $password . $salt;
        for (1..$iterations) {
            $computed = sha256_hex($computed . $salt . $password);
        }

        # Constant-time comparison
        return _constant_time_compare($computed, $stored_hash);
    }

    return 0;
}

# Constant-time string comparison to prevent timing attacks
sub _constant_time_compare {
    my ($a, $b) = @_;

    return 0 unless defined $a && defined $b;
    return 0 unless length($a) == length($b);

    my $diff = 0;
    for my $i (0 .. length($a) - 1) {
        $diff |= ord(substr($a, $i, 1)) ^ ord(substr($b, $i, 1));
    }

    return $diff == 0;
}

# Validate password strength
sub validate_password {
    my ($class, $password) = @_;

    my $min_length = HSWiki::Config->get('security', 'password_min_length') // 8;

    my @errors;

    push @errors, "Password must be at least $min_length characters"
        if length($password) < $min_length;

    return @errors ? \@errors : undef;
}

# Validate email format
sub validate_email {
    my ($class, $email) = @_;

    return "Email is required" unless $email;
    return "Invalid email format" unless $email =~ /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return;
}

# Validate username
sub validate_username {
    my ($class, $username) = @_;

    return "Username is required" unless $username;
    return "Username must be 3-32 characters" unless length($username) >= 3 && length($username) <= 32;
    return "Username can only contain letters, numbers, underscores, and hyphens"
        unless $username =~ /^[a-zA-Z0-9_-]+$/;
    return;
}

# Get session ID from request
sub get_session_id {
    my ($class, $req) = @_;
    my ($session_id, $data) = HSWiki::Session->get($req);
    return $session_id;
}

# Get user from session
sub get_session_user {
    my ($class, $req) = @_;

    my ($session_id, $data) = HSWiki::Session->get($req);
    return unless $session_id && $data->{user_id};

    return {
        user_id  => $data->{user_id},
        username => $data->{username},
        role_id  => $data->{role_id},
        role     => $data->{role},
    };
}

# Set user in session (after login) - returns session_id for cookie setting
sub set_session_user {
    my ($class, $req, $user) = @_;

    my ($session_id, $data) = HSWiki::Session->get_or_create($req);

    HSWiki::Session->set($session_id, user_id  => $user->{user_id});
    HSWiki::Session->set($session_id, username => $user->{username});
    HSWiki::Session->set($session_id, role_id  => $user->{role_id});
    HSWiki::Session->set($session_id, role     => $user->{role_name} // $user->{role});

    return $session_id;
}

# Clear user from session (logout) - returns session_id for clearing cookie
sub clear_session {
    my ($class, $req) = @_;
    my ($session_id, $data) = HSWiki::Session->get($req);
    HSWiki::Session->clear($session_id) if $session_id;
    return $session_id;
}

# Check if user is authenticated
sub is_authenticated {
    my ($class, $req) = @_;
    my ($session_id, $data) = HSWiki::Session->get($req);
    return $session_id && defined $data->{user_id};
}

# Check if user has a specific role
sub has_role {
    my ($class, $req, $role_name) = @_;

    my ($session_id, $data) = HSWiki::Session->get($req);
    return 0 unless $session_id && $data->{role};

    my $user_role = $data->{role};

    # Admin has all roles
    return 1 if $user_role eq 'admin';

    return $user_role eq $role_name;
}

# Get session value
sub get_session_value {
    my ($class, $req, $key) = @_;
    my ($session_id, $data) = HSWiki::Session->get($req);
    return $data->{$key};
}

# Check if Argon2 is available
sub has_argon2 { $HAS_ARGON2 }

1;

__END__

=head1 NAME

HSWiki::Auth - Authentication utilities for HSWiki

=head1 SYNOPSIS

    use HSWiki::Auth;

    # Hash a password
    my $hash = HSWiki::Auth->hash_password($password);

    # Verify a password
    if (HSWiki::Auth->verify_password($password, $hash)) {
        # Password is correct
    }

    # Generate API key
    my $api_key = HSWiki::Auth->generate_api_key();

    # Validate inputs
    my $errors = HSWiki::Auth->validate_password($password);
    my $error = HSWiki::Auth->validate_email($email);
    my $error = HSWiki::Auth->validate_username($username);

    # Session management
    HSWiki::Auth->set_session_user($req, $user);
    my $user = HSWiki::Auth->get_session_user($req);
    HSWiki::Auth->clear_session($req);

    # Authorization checks
    if (HSWiki::Auth->is_authenticated($req)) { ... }
    if (HSWiki::Auth->has_role($req, 'admin')) { ... }

=head1 PASSWORD HASHING

This module uses Crypt::Argon2 if available (recommended).
Falls back to SHA-256 with PBKDF2-like iterations if Argon2 is not installed.

To use Argon2 (recommended):

    cpanm Crypt::Argon2

=cut
