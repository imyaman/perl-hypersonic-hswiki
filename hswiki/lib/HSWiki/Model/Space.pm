package HSWiki::Model::Space;

use strict;
use warnings;


use HSWiki::DB;
use HSWiki::Wiki;
use Data::UUID;

our $VERSION = '0.01';

my $UUID = Data::UUID->new;

# Create a new space
sub create {
    my ($class, %args) = @_;

    my $space_id = $UUID->create_str;
    my $now = time() * 1000;

    # Generate space_key from name if not provided
    my $space_key = $args{space_key} // HSWiki::Wiki->slugify($args{name});

    my $space = {
        space_id    => $space_id,
        space_key   => $space_key,
        name        => $args{name},
        description => $args{description} // '',
        is_public   => $args{is_public} // 0,
        owner_id    => $args{owner_id},
        created_at  => $now,
        updated_at  => $now,
    };

    # Insert into main spaces table
    HSWiki::DB->insert('spaces', $space);

    # Insert into lookup table
    HSWiki::DB->insert('spaces_by_key', {
        space_key   => $space_key,
        space_id    => $space_id,
        name        => $args{name},
        description => $space->{description},
        is_public   => $space->{is_public},
        owner_id    => $args{owner_id},
    });

    # Grant admin permission to owner
    if ($args{owner_id}) {
        $class->grant_permission($space_id, $args{owner_id}, 'admin');
    }

    return $space;
}

# Find space by ID
sub find_by_id {
    my ($class, $space_id) = @_;

    return HSWiki::DB->fetch_one(
        "SELECT * FROM spaces WHERE space_id = ?",
        $space_id
    );
}

# Find space by key
sub find_by_key {
    my ($class, $space_key) = @_;

    my $row = HSWiki::DB->fetch_one(
        "SELECT space_id FROM spaces_by_key WHERE space_key = ?",
        $space_key
    );

    return unless $row;
    return $class->find_by_id($row->{space_id});
}

# Check if space key exists
sub key_exists {
    my ($class, $space_key) = @_;

    my $row = HSWiki::DB->fetch_one(
        "SELECT space_id FROM spaces_by_key WHERE space_key = ?",
        $space_key
    );

    return defined $row;
}

# Update space
sub update {
    my ($class, $space_id, %updates) = @_;

    $updates{updated_at} = time() * 1000;

    my $current = $class->find_by_id($space_id);
    return unless $current;

    # Update main table
    HSWiki::DB->update('spaces', \%updates, { space_id => $space_id });

    # Update lookup table
    HSWiki::DB->update('spaces_by_key', {
        name        => $updates{name} // $current->{name},
        description => $updates{description} // $current->{description},
        is_public   => $updates{is_public} // $current->{is_public},
    }, { space_key => $current->{space_key} });

    # Update user_spaces if name changed
    if (exists $updates{name}) {
        # This would need to update all user_spaces entries - simplified here
    }

    return $class->find_by_id($space_id);
}

# Delete space
sub delete {
    my ($class, $space_id) = @_;

    my $space = $class->find_by_id($space_id);
    return unless $space;

    # Delete from main table
    HSWiki::DB->delete('spaces', { space_id => $space_id });

    # Delete from lookup table
    HSWiki::DB->delete('spaces_by_key', { space_key => $space->{space_key} });

    # Note: Should also delete pages, permissions, etc.
    # For simplicity, not implementing cascade delete here

    return 1;
}

# List all public spaces
sub list_public {
    my ($class, %opts) = @_;

    my $limit = $opts{limit} // 100;

    return HSWiki::DB->fetch_all(
        "SELECT space_id, space_key, name, description, owner_id, created_at
         FROM spaces WHERE is_public = ? ALLOW FILTERING",
        1
    );
}

# List spaces for a user (spaces they have access to)
sub list_for_user {
    my ($class, $user_id, %opts) = @_;

    return HSWiki::DB->fetch_all(
        "SELECT space_id, space_key, space_name, permission FROM user_spaces WHERE user_id = ?",
        $user_id
    );
}

# Grant permission to user for a space
sub grant_permission {
    my ($class, $space_id, $user_id, $permission) = @_;

    my $now = time() * 1000;
    my $space = $class->find_by_id($space_id);
    return unless $space;

    # Insert into space_permissions
    HSWiki::DB->insert('space_permissions', {
        space_id   => $space_id,
        user_id    => $user_id,
        permission => $permission,
        granted_at => $now,
    });

    # Insert into user_spaces for reverse lookup
    HSWiki::DB->insert('user_spaces', {
        user_id    => $user_id,
        space_id   => $space_id,
        permission => $permission,
        space_key  => $space->{space_key},
        space_name => $space->{name},
    });

    return 1;
}

# Revoke permission from user
sub revoke_permission {
    my ($class, $space_id, $user_id) = @_;

    HSWiki::DB->delete('space_permissions', {
        space_id => $space_id,
        user_id  => $user_id,
    });

    HSWiki::DB->delete('user_spaces', {
        user_id  => $user_id,
        space_id => $space_id,
    });

    return 1;
}

# Get user's permission for a space
sub get_permission {
    my ($class, $space_id, $user_id) = @_;

    my $row = HSWiki::DB->fetch_one(
        "SELECT permission FROM space_permissions WHERE space_id = ? AND user_id = ?",
        $space_id, $user_id
    );

    return $row ? $row->{permission} : undef;
}

# Check if user can access space
sub can_access {
    my ($class, $space_id, $user_id) = @_;

    my $space = $class->find_by_id($space_id);
    return 0 unless $space;

    # Public spaces are accessible to everyone
    return 1 if $space->{is_public};

    # Check if user is owner
    return 1 if $space->{owner_id} && $space->{owner_id} eq $user_id;

    # Check permission
    my $permission = $class->get_permission($space_id, $user_id);
    return defined $permission;
}

# Check if user can write to space
sub can_write {
    my ($class, $space_id, $user_id) = @_;

    my $space = $class->find_by_id($space_id);
    return 0 unless $space;

    # Owner can always write
    return 1 if $space->{owner_id} && $space->{owner_id} eq $user_id;

    my $permission = $class->get_permission($space_id, $user_id);
    return 0 unless $permission;

    return $permission eq 'write' || $permission eq 'admin';
}

# Check if user is space admin
sub is_admin {
    my ($class, $space_id, $user_id) = @_;

    my $space = $class->find_by_id($space_id);
    return 0 unless $space;

    # Owner is admin
    return 1 if $space->{owner_id} && $space->{owner_id} eq $user_id;

    my $permission = $class->get_permission($space_id, $user_id);
    return $permission && $permission eq 'admin';
}

# List space permissions
sub list_permissions {
    my ($class, $space_id) = @_;

    return HSWiki::DB->fetch_all(
        "SELECT user_id, permission, granted_at FROM space_permissions WHERE space_id = ?",
        $space_id
    );
}

1;

__END__

=head1 NAME

HSWiki::Model::Space - Space model for HSWiki

=head1 SYNOPSIS

    use HSWiki::Model::Space;

    # Create space
    my $space = HSWiki::Model::Space->create(
        name        => 'My Documentation',
        description => 'Project documentation',
        is_public   => 1,
        owner_id    => $user_id,
    );

    # Find spaces
    my $space = HSWiki::Model::Space->find_by_id($space_id);
    my $space = HSWiki::Model::Space->find_by_key('my-documentation');

    # List spaces
    my $public = HSWiki::Model::Space->list_public;
    my $user_spaces = HSWiki::Model::Space->list_for_user($user_id);

    # Permissions
    HSWiki::Model::Space->grant_permission($space_id, $user_id, 'write');
    HSWiki::Model::Space->revoke_permission($space_id, $user_id);

    if (HSWiki::Model::Space->can_write($space_id, $user_id)) { ... }

=cut
