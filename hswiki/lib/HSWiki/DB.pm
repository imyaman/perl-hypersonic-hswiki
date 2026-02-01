package HSWiki::DB;

use strict;
use warnings;


use Cassandra::Client;
use HSWiki::Config;

our $VERSION = '0.01';

# Singleton client instance per process
my $CLIENT;
my $CLIENT_PID;

# Get or create Cassandra client connection
# Reconnects after fork (for worker processes)
sub client {
    my ($class) = @_;

    # Check if we're in a different process (forked worker)
    if ($CLIENT && $CLIENT_PID && $CLIENT_PID != $$) {
        $CLIENT = undef;
    }

    return $CLIENT if $CLIENT;

    my $config = HSWiki::Config->cassandra;

    $CLIENT = Cassandra::Client->new(
        contact_points => $config->{contact_points},
        keyspace       => $config->{keyspace},
    );
    $CLIENT->connect;
    $CLIENT_PID = $$;

    return $CLIENT;
}

# Execute a CQL query
# Usage: HSWiki::DB->execute($query, @params)
# Returns: result object or undef on error
sub execute {
    my ($class, $query, @params) = @_;

    my $client = $class->client;

    if (@params) {
        return $client->execute($query, \@params);
    }
    return $client->execute($query);
}

# Execute with pagination callback
# Usage: HSWiki::DB->each_page($query, \@params, $page_size, sub { my $result = shift; ... })
sub each_page {
    my ($class, $query, $params, $page_size, $callback) = @_;

    my $client = $class->client;
    $params //= [];

    $client->each_page($query, $params, $page_size, $callback);
}

# Convert array row to hashref using column names
sub _row_to_hash {
    my ($columns, $row) = @_;
    return unless $row && $columns;

    my %hash;
    for my $i (0 .. $#$columns) {
        $hash{$columns->[$i]} = $row->[$i];
    }
    return \%hash;
}

# Get all rows from a query (convenience method)
# Warning: Use with caution on large result sets
sub fetch_all {
    my ($class, $query, @params) = @_;

    my $client = $class->client;
    my @all_rows;

    $client->each_page($query, \@params, undef, sub {
        my $result = shift;
        my $columns = $result->column_names;
        for my $row (@{ $result->rows // [] }) {
            push @all_rows, _row_to_hash($columns, $row);
        }
    });

    return \@all_rows;
}

# Get a single row
sub fetch_one {
    my ($class, $query, @params) = @_;

    my $client = $class->client;
    my $found_row;

    $client->each_page($query, \@params, undef, sub {
        my $result = shift;
        my $rows = $result->rows // [];
        if (@$rows && !$found_row) {
            $found_row = _row_to_hash($result->column_names, $rows->[0]);
        }
    });

    return $found_row;
}

# Insert helper with named columns
# Usage: HSWiki::DB->insert('users', { user_id => $id, username => $name, ... })
sub insert {
    my ($class, $table, $data) = @_;

    my @columns = keys %$data;
    my @placeholders = map { '?' } @columns;
    my @values = map { $data->{$_} } @columns;

    my $query = sprintf(
        "INSERT INTO %s (%s) VALUES (%s)",
        $table,
        join(', ', @columns),
        join(', ', @placeholders)
    );

    return $class->execute($query, @values);
}

# Update helper
# Usage: HSWiki::DB->update('users', { username => $name }, { user_id => $id })
sub update {
    my ($class, $table, $data, $where) = @_;

    my @set_parts;
    my @values;

    for my $col (keys %$data) {
        push @set_parts, "$col = ?";
        push @values, $data->{$col};
    }

    my @where_parts;
    for my $col (keys %$where) {
        push @where_parts, "$col = ?";
        push @values, $where->{$col};
    }

    my $query = sprintf(
        "UPDATE %s SET %s WHERE %s",
        $table,
        join(', ', @set_parts),
        join(' AND ', @where_parts)
    );

    return $class->execute($query, @values);
}

# Delete helper
# Usage: HSWiki::DB->delete('users', { user_id => $id })
sub delete {
    my ($class, $table, $where) = @_;

    my @where_parts;
    my @values;

    for my $col (keys %$where) {
        push @where_parts, "$col = ?";
        push @values, $where->{$col};
    }

    my $query = sprintf(
        "DELETE FROM %s WHERE %s",
        $table,
        join(' AND ', @where_parts)
    );

    return $class->execute($query, @values);
}

# Check if a row exists
sub exists {
    my ($class, $table, $where) = @_;

    my @where_parts;
    my @values;

    for my $col (keys %$where) {
        push @where_parts, "$col = ?";
        push @values, $where->{$col};
    }

    my $query = sprintf(
        "SELECT COUNT(*) FROM %s WHERE %s",
        $table,
        join(' AND ', @where_parts)
    );

    my $row = $class->fetch_one($query, @values);
    return $row && $row->{count} > 0;
}

# Initialize schema (create keyspace and tables)
sub init_schema {
    my ($class) = @_;

    my $keyspace = HSWiki::Config->get('cassandra', 'keyspace');

    # Create keyspace
    $class->execute(qq{
        CREATE KEYSPACE IF NOT EXISTS $keyspace
        WITH replication = {
            'class': 'NetworkTopologyStrategy',
            'datacenter1': 3
        }
    });

    # Use keyspace
    $class->execute("USE $keyspace");

    # Create tables
    my @tables = (
        # Users
        q{
            CREATE TABLE IF NOT EXISTS users (
                user_id UUID PRIMARY KEY,
                username TEXT,
                email TEXT,
                password_hash TEXT,
                role_id UUID,
                api_key TEXT,
                is_active BOOLEAN,
                created_at TIMESTAMP,
                updated_at TIMESTAMP
            )
        },
        q{
            CREATE TABLE IF NOT EXISTS users_by_username (
                username TEXT PRIMARY KEY,
                user_id UUID,
                password_hash TEXT,
                role_id UUID,
                is_active BOOLEAN
            )
        },
        q{
            CREATE TABLE IF NOT EXISTS users_by_email (
                email TEXT PRIMARY KEY,
                user_id UUID
            )
        },
        q{
            CREATE TABLE IF NOT EXISTS users_by_api_key (
                api_key TEXT PRIMARY KEY,
                user_id UUID,
                is_active BOOLEAN
            )
        },

        # Roles
        q{
            CREATE TABLE IF NOT EXISTS roles (
                role_id UUID PRIMARY KEY,
                role_name TEXT,
                permissions SET<TEXT>,
                description TEXT,
                created_at TIMESTAMP
            )
        },
        q{
            CREATE TABLE IF NOT EXISTS roles_by_name (
                role_name TEXT PRIMARY KEY,
                role_id UUID,
                permissions SET<TEXT>
            )
        },

        # Spaces
        q{
            CREATE TABLE IF NOT EXISTS spaces (
                space_id UUID PRIMARY KEY,
                space_key TEXT,
                name TEXT,
                description TEXT,
                is_public BOOLEAN,
                owner_id UUID,
                created_at TIMESTAMP,
                updated_at TIMESTAMP
            )
        },
        q{
            CREATE TABLE IF NOT EXISTS spaces_by_key (
                space_key TEXT PRIMARY KEY,
                space_id UUID,
                name TEXT,
                description TEXT,
                is_public BOOLEAN,
                owner_id UUID
            )
        },
        q{
            CREATE TABLE IF NOT EXISTS space_permissions (
                space_id UUID,
                user_id UUID,
                permission TEXT,
                granted_at TIMESTAMP,
                PRIMARY KEY (space_id, user_id)
            )
        },
        q{
            CREATE TABLE IF NOT EXISTS user_spaces (
                user_id UUID,
                space_id UUID,
                permission TEXT,
                space_key TEXT,
                space_name TEXT,
                PRIMARY KEY (user_id, space_id)
            )
        },

        # Pages
        q{
            CREATE TABLE IF NOT EXISTS pages (
                space_id UUID,
                page_id UUID,
                slug TEXT,
                title TEXT,
                content TEXT,
                content_html TEXT,
                author_id UUID,
                version INT,
                created_at TIMESTAMP,
                updated_at TIMESTAMP,
                PRIMARY KEY (space_id, page_id)
            )
        },
        q{
            CREATE TABLE IF NOT EXISTS pages_by_slug (
                space_id UUID,
                page_slug TEXT,
                page_id UUID,
                title TEXT,
                version INT,
                updated_at TIMESTAMP,
                PRIMARY KEY (space_id, page_slug)
            )
        },
        q{
            CREATE TABLE IF NOT EXISTS page_versions (
                page_id UUID,
                version INT,
                title TEXT,
                content TEXT,
                content_html TEXT,
                author_id UUID,
                created_at TIMESTAMP,
                change_summary TEXT,
                PRIMARY KEY (page_id, version)
            ) WITH CLUSTERING ORDER BY (version DESC)
        },
    );

    for my $table_ddl (@tables) {
        $class->execute($table_ddl);
    }

    return 1;
}

# Disconnect (for cleanup)
sub disconnect {
    my ($class) = @_;

    if ($CLIENT) {
        $CLIENT->shutdown if $CLIENT->can('shutdown');
        $CLIENT = undef;
    }
}

# Reset client (for testing)
sub _reset {
    $CLIENT = undef;
}

1;

__END__

=head1 NAME

HSWiki::DB - Cassandra database wrapper for HSWiki

=head1 SYNOPSIS

    use HSWiki::DB;

    # Execute raw query
    my $result = HSWiki::DB->execute(
        "SELECT * FROM users WHERE user_id = ?",
        $user_id
    );

    # Fetch all rows
    my $rows = HSWiki::DB->fetch_all("SELECT * FROM spaces WHERE is_public = ?", 1);

    # Fetch single row
    my $user = HSWiki::DB->fetch_one(
        "SELECT * FROM users_by_username WHERE username = ?",
        $username
    );

    # Insert
    HSWiki::DB->insert('users', {
        user_id       => $id,
        username      => $username,
        email         => $email,
        password_hash => $hash,
    });

    # Update
    HSWiki::DB->update('users',
        { email => $new_email },
        { user_id => $id }
    );

    # Delete
    HSWiki::DB->delete('users', { user_id => $id });

    # Pagination
    HSWiki::DB->each_page(
        "SELECT * FROM pages WHERE space_id = ?",
        [$space_id],
        100,
        sub {
            my $result = shift;
            for my $row (@{ $result->rows }) {
                # process row
            }
        }
    );

=cut
