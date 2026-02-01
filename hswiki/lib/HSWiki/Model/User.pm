package HSWiki::Model::User;

use strict;
use warnings;


use HSWiki::DB;
use HSWiki::Auth;
use Data::UUID;

our $VERSION = '0.01';

my $UUID = Data::UUID->new;

# Create a new user
sub create {
    my ($class, %args) = @_;

    my $user_id = $UUID->create_str;
    my $now = time() * 1000;  # Cassandra timestamp in milliseconds

    # Hash the password
    my $password_hash = HSWiki::Auth->hash_password($args{password});

    # Generate API key
    my $api_key = HSWiki::Auth->generate_api_key;

    my $user = {
        user_id       => $user_id,
        username      => $args{username},
        email         => $args{email},
        password_hash => $password_hash,
        role_id       => $args{role_id},
        api_key       => $api_key,
        is_active     => 1,
        created_at    => $now,
        updated_at    => $now,
    };

    # Insert into main users table
    HSWiki::DB->insert('users', $user);

    # Insert into lookup tables
    HSWiki::DB->insert('users_by_username', {
        username      => $args{username},
        user_id       => $user_id,
        password_hash => $password_hash,
        role_id       => $args{role_id},
        is_active     => 1,
    });

    HSWiki::DB->insert('users_by_email', {
        email   => $args{email},
        user_id => $user_id,
    });

    HSWiki::DB->insert('users_by_api_key', {
        api_key   => $api_key,
        user_id   => $user_id,
        is_active => 1,
    });

    return $user;
}

# Find user by ID
sub find_by_id {
    my ($class, $user_id) = @_;

    return HSWiki::DB->fetch_one(
        "SELECT * FROM users WHERE user_id = ?",
        $user_id
    );
}

# Find user by username
sub find_by_username {
    my ($class, $username) = @_;

    return HSWiki::DB->fetch_one(
        "SELECT * FROM users_by_username WHERE username = ?",
        $username
    );
}

# Find user by email
sub find_by_email {
    my ($class, $email) = @_;

    my $row = HSWiki::DB->fetch_one(
        "SELECT user_id FROM users_by_email WHERE email = ?",
        $email
    );

    return unless $row;
    return $class->find_by_id($row->{user_id});
}

# Find user by API key
sub find_by_api_key {
    my ($class, $api_key) = @_;

    my $row = HSWiki::DB->fetch_one(
        "SELECT user_id, is_active FROM users_by_api_key WHERE api_key = ?",
        $api_key
    );

    return unless $row && $row->{is_active};
    return $class->find_by_id($row->{user_id});
}

# Check if username exists
sub username_exists {
    my ($class, $username) = @_;

    my $row = HSWiki::DB->fetch_one(
        "SELECT user_id FROM users_by_username WHERE username = ?",
        $username
    );

    return defined $row;
}

# Check if email exists
sub email_exists {
    my ($class, $email) = @_;

    my $row = HSWiki::DB->fetch_one(
        "SELECT user_id FROM users_by_email WHERE email = ?",
        $email
    );

    return defined $row;
}

# Update user
sub update {
    my ($class, $user_id, %updates) = @_;

    $updates{updated_at} = time() * 1000;

    # Get current user for lookup table updates
    my $current = $class->find_by_id($user_id);
    return unless $current;

    # Update main table
    HSWiki::DB->update('users', \%updates, { user_id => $user_id });

    # Update lookup tables if relevant fields changed
    if (exists $updates{password_hash} || exists $updates{role_id} || exists $updates{is_active}) {
        HSWiki::DB->update('users_by_username', {
            password_hash => $updates{password_hash} // $current->{password_hash},
            role_id       => $updates{role_id} // $current->{role_id},
            is_active     => $updates{is_active} // $current->{is_active},
        }, { username => $current->{username} });
    }

    if (exists $updates{is_active}) {
        HSWiki::DB->update('users_by_api_key', {
            is_active => $updates{is_active},
        }, { api_key => $current->{api_key} });
    }

    return $class->find_by_id($user_id);
}

# Update user's role
sub update_role {
    my ($class, $user_id, $role_id) = @_;
    return $class->update($user_id, role_id => $role_id);
}

# Deactivate user (soft delete)
sub deactivate {
    my ($class, $user_id) = @_;
    return $class->update($user_id, is_active => 0);
}

# Reactivate user
sub reactivate {
    my ($class, $user_id) = @_;
    return $class->update($user_id, is_active => 1);
}

# Change password
sub change_password {
    my ($class, $user_id, $new_password) = @_;

    my $password_hash = HSWiki::Auth->hash_password($new_password);
    return $class->update($user_id, password_hash => $password_hash);
}

# Regenerate API key
sub regenerate_api_key {
    my ($class, $user_id) = @_;

    my $current = $class->find_by_id($user_id);
    return unless $current;

    # Delete old API key entry
    HSWiki::DB->delete('users_by_api_key', { api_key => $current->{api_key} });

    # Generate new key
    my $new_api_key = HSWiki::Auth->generate_api_key;

    # Update user
    $class->update($user_id, api_key => $new_api_key);

    # Insert new API key lookup
    HSWiki::DB->insert('users_by_api_key', {
        api_key   => $new_api_key,
        user_id   => $user_id,
        is_active => $current->{is_active},
    });

    return $new_api_key;
}

# List all users (with pagination)
sub list_all {
    my ($class, %opts) = @_;

    my $limit = $opts{limit} // 100;
    my @users;

    HSWiki::DB->each_page(
        "SELECT user_id, username, email, role_id, is_active, created_at FROM users",
        [],
        $limit,
        sub {
            my $result = shift;
            push @users, @{ $result->rows // [] };
        }
    );

    return \@users;
}

# Authenticate user (for login)
sub authenticate {
    my ($class, $username, $password) = @_;

    my $user = $class->find_by_username($username);
    return unless $user;
    return unless $user->{is_active};

    if (HSWiki::Auth->verify_password($password, $user->{password_hash})) {
        # Get full user data
        return $class->find_by_id($user->{user_id});
    }

    return;
}

# Convert to safe format (no password hash)
sub to_safe {
    my ($class, $user) = @_;

    return unless $user;

    return {
        user_id    => $user->{user_id},
        username   => $user->{username},
        email      => $user->{email},
        role_id    => $user->{role_id},
        is_active  => $user->{is_active},
        created_at => $user->{created_at},
        updated_at => $user->{updated_at},
    };
}

1;

__END__

=head1 NAME

HSWiki::Model::User - User model for HSWiki

=head1 SYNOPSIS

    use HSWiki::Model::User;

    # Create user
    my $user = HSWiki::Model::User->create(
        username => 'johndoe',
        email    => 'john@example.com',
        password => 'secret123',
        role_id  => $role_id,
    );

    # Find users
    my $user = HSWiki::Model::User->find_by_id($user_id);
    my $user = HSWiki::Model::User->find_by_username('johndoe');
    my $user = HSWiki::Model::User->find_by_email('john@example.com');
    my $user = HSWiki::Model::User->find_by_api_key($api_key);

    # Authenticate
    my $user = HSWiki::Model::User->authenticate('johndoe', 'secret123');

    # Update
    HSWiki::Model::User->update_role($user_id, $new_role_id);
    HSWiki::Model::User->change_password($user_id, 'newpassword');
    HSWiki::Model::User->deactivate($user_id);

=cut
