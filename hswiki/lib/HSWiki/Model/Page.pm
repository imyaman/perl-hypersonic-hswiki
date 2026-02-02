package HSWiki::Model::Page;

use strict;
use warnings;


use HSWiki::DB;
use HSWiki::Wiki;
use Data::UUID;

our $VERSION = '0.01';

my $UUID = Data::UUID->new;

# Create a new page
sub create {
    my ($class, %args) = @_;

    my $page_id = $UUID->create_str;
    my $now = time() * 1000;

    # Generate slug from title if not provided
    my $slug = $args{slug} // HSWiki::Wiki->slugify($args{title});

    # Render content to HTML with space context for link resolution
    my $content_html = HSWiki::Wiki->render_safe(
        $args{content},
        space_id => $args{space_id},
    );

    my $page = {
        space_id     => $args{space_id},
        page_id      => $page_id,
        slug         => $slug,
        title        => $args{title},
        content      => $args{content} // '',
        content_html => $content_html,
        author_id    => $args{author_id},
        version      => 1,
        created_at   => $now,
        updated_at   => $now,
    };

    # Insert into main pages table
    HSWiki::DB->insert('pages', $page);

    # Insert into slug lookup table
    HSWiki::DB->insert('pages_by_slug', {
        space_id   => $args{space_id},
        page_slug  => $slug,
        page_id    => $page_id,
        title      => $args{title},
        version    => 1,
        updated_at => $now,
    });

    # Create initial version in history
    HSWiki::DB->insert('page_versions', {
        page_id        => $page_id,
        version        => 1,
        title          => $args{title},
        content        => $args{content} // '',
        content_html   => $content_html,
        author_id      => $args{author_id},
        created_at     => $now,
        change_summary => 'Initial version',
    });

    return $page;
}

# Find page by ID within a space
sub find_by_id {
    my ($class, $space_id, $page_id) = @_;

    return HSWiki::DB->fetch_one(
        "SELECT * FROM pages WHERE space_id = ? AND page_id = ?",
        $space_id, $page_id
    );
}

# Find page by slug within a space
sub find_by_slug {
    my ($class, $space_id, $slug) = @_;

    my $row = HSWiki::DB->fetch_one(
        "SELECT page_id FROM pages_by_slug WHERE space_id = ? AND page_slug = ?",
        $space_id, $slug
    );

    return unless $row;
    return $class->find_by_id($space_id, $row->{page_id});
}

# Check if slug exists in space
sub slug_exists {
    my ($class, $space_id, $slug) = @_;

    my $row = HSWiki::DB->fetch_one(
        "SELECT page_id FROM pages_by_slug WHERE space_id = ? AND page_slug = ?",
        $space_id, $slug
    );

    return defined $row;
}

# Update page (creates new version)
sub update {
    my ($class, $space_id, $page_id, %updates) = @_;

    my $now = time() * 1000;

    my $current = $class->find_by_id($space_id, $page_id);
    return unless $current;

    my $new_version = ($current->{version} // 0) + 1;

    # Re-render content if changed (with space context for link resolution)
    my $content = $updates{content} // $current->{content};
    my $content_html = HSWiki::Wiki->render_safe($content, space_id => $space_id);

    # Update main page
    HSWiki::DB->update('pages', {
        title        => $updates{title} // $current->{title},
        content      => $content,
        content_html => $content_html,
        author_id    => $updates{author_id} // $current->{author_id},
        version      => $new_version,
        updated_at   => $now,
    }, {
        space_id => $space_id,
        page_id  => $page_id,
    });

    # Update slug lookup
    HSWiki::DB->update('pages_by_slug', {
        title      => $updates{title} // $current->{title},
        version    => $new_version,
        updated_at => $now,
    }, {
        space_id  => $space_id,
        page_slug => $current->{slug},
    });

    # Create new version in history
    HSWiki::DB->insert('page_versions', {
        page_id        => $page_id,
        version        => $new_version,
        title          => $updates{title} // $current->{title},
        content        => $content,
        content_html   => $content_html,
        author_id      => $updates{author_id} // $current->{author_id},
        created_at     => $now,
        change_summary => $updates{change_summary} // '',
    });

    return $class->find_by_id($space_id, $page_id);
}

# Delete page
sub delete {
    my ($class, $space_id, $page_id) = @_;

    my $page = $class->find_by_id($space_id, $page_id);
    return unless $page;

    # Delete from main table
    HSWiki::DB->delete('pages', {
        space_id => $space_id,
        page_id  => $page_id,
    });

    # Delete from slug lookup
    HSWiki::DB->delete('pages_by_slug', {
        space_id  => $space_id,
        page_slug => $page->{slug},
    });

    # Note: Not deleting version history for audit purposes
    # Could add a purge method to delete versions too

    return 1;
}

# List pages in a space
sub list_by_space {
    my ($class, $space_id, %opts) = @_;

    my $limit = $opts{limit} // 100;

    return HSWiki::DB->fetch_all(
        "SELECT page_id, slug, title, version, updated_at FROM pages WHERE space_id = ?",
        $space_id
    );
}

# Get page version history
sub get_versions {
    my ($class, $page_id, %opts) = @_;

    my $limit = $opts{limit} // 50;

    return HSWiki::DB->fetch_all(
        "SELECT version, title, author_id, created_at, change_summary
         FROM page_versions WHERE page_id = ? ORDER BY version DESC",
        $page_id
    );
}

# Get specific version of a page
sub get_version {
    my ($class, $page_id, $version) = @_;

    return HSWiki::DB->fetch_one(
        "SELECT * FROM page_versions WHERE page_id = ? AND version = ?",
        $page_id, $version
    );
}

# Restore a page to a specific version
sub restore_version {
    my ($class, $space_id, $page_id, $version, $author_id) = @_;

    my $old_version = $class->get_version($page_id, $version);
    return unless $old_version;

    return $class->update($space_id, $page_id,
        title          => $old_version->{title},
        content        => $old_version->{content},
        author_id      => $author_id,
        change_summary => "Restored from version $version",
    );
}

# Search pages by title (simple LIKE search)
sub search {
    my ($class, $space_id, $query, %opts) = @_;

    # Note: Cassandra doesn't support LIKE queries well
    # This is a simplified implementation
    # For production, use a search engine like Elasticsearch

    my @pages;
    my $all_pages = $class->list_by_space($space_id);

    for my $page (@$all_pages) {
        if ($page->{title} =~ /$query/i) {
            push @pages, $page;
        }
    }

    return \@pages;
}

# Get page count for a space
sub count_by_space {
    my ($class, $space_id) = @_;

    my $row = HSWiki::DB->fetch_one(
        "SELECT COUNT(*) as count FROM pages WHERE space_id = ?",
        $space_id
    );

    return $row ? $row->{count} : 0;
}

# Convert page to API response format
sub to_response {
    my ($class, $page, %opts) = @_;

    return unless $page;

    my $response = {
        page_id    => $page->{page_id},
        slug       => $page->{slug},
        title      => $page->{title},
        version    => $page->{version},
        author_id  => $page->{author_id},
        created_at => $page->{created_at},
        updated_at => $page->{updated_at},
    };

    # Include content based on options
    if ($opts{include_content}) {
        $response->{content} = $page->{content};
    }
    if ($opts{include_html}) {
        # Re-render content to resolve wiki links with current page titles
        $response->{content_html} = HSWiki::Wiki->render_safe(
            $page->{content},
            space_id => $page->{space_id},
        );
    }

    return $response;
}

1;

__END__

=head1 NAME

HSWiki::Model::Page - Page model for HSWiki

=head1 SYNOPSIS

    use HSWiki::Model::Page;

    # Create page
    my $page = HSWiki::Model::Page->create(
        space_id  => $space_id,
        space_key => 'docs',
        title     => 'Getting Started',
        content   => '= Welcome =\n\nThis is the getting started guide.',
        author_id => $user_id,
    );

    # Find pages
    my $page = HSWiki::Model::Page->find_by_id($space_id, $page_id);
    my $page = HSWiki::Model::Page->find_by_slug($space_id, 'getting-started');

    # Update page
    HSWiki::Model::Page->update($space_id, $page_id,
        content        => $new_content,
        author_id      => $user_id,
        change_summary => 'Updated introduction',
    );

    # Version history
    my $versions = HSWiki::Model::Page->get_versions($page_id);
    my $old = HSWiki::Model::Page->get_version($page_id, 2);
    HSWiki::Model::Page->restore_version($space_id, $page_id, 2, $user_id);

    # List and search
    my $pages = HSWiki::Model::Page->list_by_space($space_id);
    my $results = HSWiki::Model::Page->search($space_id, 'getting');

=cut
