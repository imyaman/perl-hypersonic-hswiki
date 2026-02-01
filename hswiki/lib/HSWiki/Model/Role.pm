package HSWiki::Model::Role;

use strict;
use warnings;


use HSWiki::DB;
use HSWiki::Config;
use Data::UUID;

our $VERSION = '0.01';

my $UUID = Data::UUID->new;

# Default role definitions
my %DEFAULT_ROLES = (
    admin => {
        permissions => [
            'user:read', 'user:write', 'user:delete', 'role:manage',
            'space:read', 'space:write', 'space:delete', 'space:admin',
            'page:read', 'page:write', 'page:delete',
        ],
        description => 'Administrator with full system access',
    },
    editor => {
        permissions => ['space:read', 'space:write', 'page:read', 'page:write'],
        description => 'Can create spaces and edit pages',
    },
    viewer => {
        permissions => ['space:read', 'page:read'],
        description => 'Read-only access to spaces and pages',
    },
);

# Create a new role
sub create {
    my ($class, %args) = @_;

    my $role_id = $UUID->create_str;
    my $now = time() * 1000;

    my $permissions = $args{permissions} // [];
    $permissions = [$permissions] unless ref $permissions eq 'ARRAY';

    my $role = {
        role_id     => $role_id,
        role_name   => $args{role_name},
        permissions => $permissions,
        description => $args{description} // '',
        created_at  => $now,
    };

    # Insert into roles table
    HSWiki::DB->execute(
        "INSERT INTO roles (role_id, role_name, permissions, description, created_at) VALUES (?, ?, ?, ?, ?)",
        $role_id, $args{role_name}, $permissions, $role->{description}, $now
    );

    # Insert into lookup table
    HSWiki::DB->execute(
        "INSERT INTO roles_by_name (role_name, role_id, permissions) VALUES (?, ?, ?)",
        $args{role_name}, $role_id, $permissions
    );

    return $role;
}

# Find role by ID
sub find_by_id {
    my ($class, $role_id) = @_;

    return HSWiki::DB->fetch_one(
        "SELECT * FROM roles WHERE role_id = ?",
        $role_id
    );
}

# Find role by name
sub find_by_name {
    my ($class, $role_name) = @_;

    return HSWiki::DB->fetch_one(
        "SELECT * FROM roles_by_name WHERE role_name = ?",
        $role_name
    );
}

# Get role ID by name
sub get_role_id {
    my ($class, $role_name) = @_;

    my $role = $class->find_by_name($role_name);
    return $role ? $role->{role_id} : undef;
}

# Check if role exists
sub exists {
    my ($class, $role_name) = @_;
    return defined $class->find_by_name($role_name);
}

# List all roles
sub list_all {
    my ($class) = @_;

    return HSWiki::DB->fetch_all("SELECT * FROM roles");
}

# Update role permissions
sub update_permissions {
    my ($class, $role_id, $permissions) = @_;

    $permissions = [$permissions] unless ref $permissions eq 'ARRAY';

    my $role = $class->find_by_id($role_id);
    return unless $role;

    # Update roles table
    HSWiki::DB->execute(
        "UPDATE roles SET permissions = ? WHERE role_id = ?",
        $permissions, $role_id
    );

    # Update lookup table
    HSWiki::DB->execute(
        "UPDATE roles_by_name SET permissions = ? WHERE role_name = ?",
        $permissions, $role->{role_name}
    );

    return $class->find_by_id($role_id);
}

# Delete role (use with caution)
sub delete {
    my ($class, $role_id) = @_;

    my $role = $class->find_by_id($role_id);
    return unless $role;

    HSWiki::DB->delete('roles', { role_id => $role_id });
    HSWiki::DB->delete('roles_by_name', { role_name => $role->{role_name} });

    return 1;
}

# Check if a role has a specific permission
sub has_permission {
    my ($class, $role_id, $permission) = @_;

    my $role = $class->find_by_id($role_id);
    return 0 unless $role && $role->{permissions};

    my %perms = map { $_ => 1 } @{ $role->{permissions} };
    return exists $perms{$permission};
}

# Get all permissions for a role
sub get_permissions {
    my ($class, $role_id) = @_;

    my $role = $class->find_by_id($role_id);
    return [] unless $role;

    return $role->{permissions} // [];
}

# Initialize default roles
sub init_defaults {
    my ($class) = @_;

    for my $role_name (keys %DEFAULT_ROLES) {
        next if $class->exists($role_name);

        $class->create(
            role_name   => $role_name,
            permissions => $DEFAULT_ROLES{$role_name}{permissions},
            description => $DEFAULT_ROLES{$role_name}{description},
        );
    }

    return 1;
}

# Get default editor role ID (for new users)
sub default_role_id {
    my ($class) = @_;

    my $role = $class->find_by_name('editor');
    return $role ? $role->{role_id} : undef;
}

# Get admin role ID
sub admin_role_id {
    my ($class) = @_;

    my $role = $class->find_by_name('admin');
    return $role ? $role->{role_id} : undef;
}

# Check if a role is admin
sub is_admin {
    my ($class, $role_id) = @_;

    my $admin_id = $class->admin_role_id;
    return $admin_id && $role_id eq $admin_id;
}

1;

__END__

=head1 NAME

HSWiki::Model::Role - Role model for HSWiki

=head1 SYNOPSIS

    use HSWiki::Model::Role;

    # Initialize default roles
    HSWiki::Model::Role->init_defaults;

    # Find roles
    my $role = HSWiki::Model::Role->find_by_id($role_id);
    my $role = HSWiki::Model::Role->find_by_name('admin');

    # Check permissions
    if (HSWiki::Model::Role->has_permission($role_id, 'page:write')) { ... }

    # Get role IDs
    my $viewer_id = HSWiki::Model::Role->default_role_id;
    my $admin_id = HSWiki::Model::Role->admin_role_id;

    # Create custom role
    my $role = HSWiki::Model::Role->create(
        role_name   => 'moderator',
        permissions => ['space:read', 'page:read', 'page:write', 'page:delete'],
        description => 'Can moderate content',
    );

=cut
