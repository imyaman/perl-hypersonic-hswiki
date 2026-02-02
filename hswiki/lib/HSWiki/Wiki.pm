package HSWiki::Wiki;

use strict;
use warnings;


use Text::WikiFormat ();
use HTML::Entities qw(encode_entities);

our $VERSION = '0.01';

# Current space_id for link resolution (set during render)
my $_current_space_id;

# Render wiki markup to HTML
sub render {
    my ($class, $content, %opts) = @_;

    return '' unless defined $content;

    # Store space_id for link resolution
    $_current_space_id = $opts{space_id};

    # Pre-process custom syntax before Text::WikiFormat
    $content = _preprocess($content, %opts);

    # Render with Text::WikiFormat
    # Disable extended links - we handle [[Page]] ourselves in postprocess
    my $html = Text::WikiFormat::format($content, {}, {
        extended       => 0,
        implicit_links => 0,
        absolute_links => 1,
    });

    # Post-process for additional features
    $html = _postprocess($html, %opts);

    return $html;
}

# Placeholder for wiki links during Text::WikiFormat processing
my @_wiki_links;

# Pre-process custom wiki syntax
sub _preprocess {
    my ($content, %opts) = @_;

    # Reset wiki links array
    @_wiki_links = ();

    # Convert ```code``` blocks to wiki code format
    $content =~ s/```(\w*)\n(.*?)```/_format_code_block($1, $2)/ges;

    # Convert **bold** to wiki strong
    $content =~ s/\*\*(.+?)\*\*/'''$1'''/g;

    # Convert *italic* to wiki emphasis (but not when part of **)
    $content =~ s/(?<!\*)(?<!')\*([^*]+?)\*(?!\*)(?!')/''\Q$1\E''/g;

    # Convert # headers to wiki headers
    $content =~ s/^(#{1,6})\s*(.+)$/_format_header(length($1), $2)/gem;

    # Convert - lists to wiki format
    $content =~ s/^-\s+(.+)$/* $1/gm;

    # Convert 1. numbered lists to wiki format
    $content =~ s/^\d+\.\s+(.+)$/# $1/gm;

    # Replace wiki links [[Page]] or [[Page|Text]] with placeholders
    # to prevent Text::WikiFormat from processing them
    $content =~ s/\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/_store_wiki_link($1, $2)/ge;

    return $content;
}

# Store wiki link and return placeholder
sub _store_wiki_link {
    my ($target, $text) = @_;
    my $index = scalar @_wiki_links;
    push @_wiki_links, { target => $target, text => $text };
    return "WIKILINK_PLACEHOLDER_${index}_END";
}

# Format wiki link with page title resolution
sub _format_link {
    my ($target, $text) = @_;
    my $slug = _slugify($target);
    my $css_class = 'wiki-link';
    my $display_text;

    # If custom text provided, always use it
    if (defined $text && $text ne '') {
        $display_text = $text;
    }
    # Otherwise, try to resolve page title from database
    elsif ($_current_space_id) {
        require HSWiki::Model::Page;
        my $page = HSWiki::Model::Page->find_by_slug($_current_space_id, $slug);
        if ($page) {
            $display_text = $page->{title};
        } else {
            # Page doesn't exist - use original text and mark as missing
            $display_text = $target;
            $css_class = 'wiki-link wiki-link-missing';
        }
    }
    else {
        # No space context - use original text
        $display_text = $target;
    }

    # Generate link with data-slug for JavaScript navigation
    my $escaped_text = encode_entities($display_text);
    my $escaped_slug = encode_entities($slug);
    return qq{<a href="#" class="$css_class" data-slug="$escaped_slug">$escaped_text</a>};
}

# Format code block
sub _format_code_block {
    my ($lang, $code) = @_;
    $code = encode_entities($code);
    if ($lang) {
        return qq{\n<pre><code class="language-$lang">$code</code></pre>\n};
    }
    return qq{\n<pre><code>$code</code></pre>\n};
}

# Format header
sub _format_header {
    my ($level, $text) = @_;
    return "=" x $level . " $text " . "=" x $level;
}

# Post-process HTML for additional features
sub _postprocess {
    my ($html, %opts) = @_;

    # Restore wiki link placeholders with actual HTML links
    $html =~ s/WIKILINK_PLACEHOLDER_(\d+)_END/_restore_wiki_link($1)/ge;

    # Auto-link URLs (but not already linked ones)
    $html =~ s{(?<![">])(https?://[^\s<>"]+)}{<a href="$1" rel="nofollow">$1</a>}g;

    return $html;
}

# Restore wiki link from placeholder
sub _restore_wiki_link {
    my ($index) = @_;
    return '' unless defined $_wiki_links[$index];
    my $link = $_wiki_links[$index];
    return _format_link($link->{target}, $link->{text});
}

# Convert text to URL-safe slug
sub _slugify {
    my ($text) = @_;

    $text = lc($text);
    $text =~ s/[^\w\s-]//g;     # Remove non-word chars
    $text =~ s/[\s_]+/-/g;       # Replace spaces/underscores with hyphens
    $text =~ s/^-+|-+$//g;       # Trim leading/trailing hyphens

    return $text;
}

# Public slugify method
sub slugify {
    my ($class, $text) = @_;
    return _slugify($text);
}

# Extract text preview from content (first N characters)
sub preview {
    my ($class, $content, $length) = @_;
    $length //= 200;

    return '' unless defined $content;

    # Strip wiki markup
    my $text = $content;
    $text =~ s/'''(.+?)'''/$1/g;    # bold
    $text =~ s/''(.+?)''/$1/g;       # italic
    $text =~ s/={1,6}\s*(.+?)\s*={1,6}/$1/g;  # headers
    $text =~ s/\[\[(.+?)(?:\|.+?)?\]\]/$1/g;  # links
    $text =~ s/```.*?```//gs;         # code blocks
    $text =~ s/[*#]+\s*//g;           # list markers

    # Trim and truncate
    $text =~ s/^\s+|\s+$//g;
    $text =~ s/\s+/ /g;

    if (length($text) > $length) {
        $text = substr($text, 0, $length);
        $text =~ s/\s+\S*$/.../;
    }

    return $text;
}

# Sanitize HTML (basic XSS prevention)
sub sanitize_html {
    my ($class, $html) = @_;

    return '' unless defined $html;

    # Remove script tags
    $html =~ s/<script[^>]*>.*?<\/script>//gis;

    # Remove event handlers
    $html =~ s/\s+on\w+\s*=\s*["'][^"']*["']//gi;

    # Remove javascript: URLs
    $html =~ s/href\s*=\s*["']javascript:[^"']*["']/href="#"/gi;

    # Remove style tags
    $html =~ s/<style[^>]*>.*?<\/style>//gis;

    return $html;
}

# Render and sanitize in one call
sub render_safe {
    my ($class, $content, %opts) = @_;

    my $html = $class->render($content, %opts);
    return $class->sanitize_html($html);
}

1;

__END__

=head1 NAME

HSWiki::Wiki - Wiki markup rendering for HSWiki

=head1 SYNOPSIS

    use HSWiki::Wiki;

    # Render wiki markup to HTML
    my $html = HSWiki::Wiki->render($content);

    # Render with base URL for links
    my $html = HSWiki::Wiki->render($content, base_url => '/wiki/myspace');

    # Render and sanitize (safe for display)
    my $html = HSWiki::Wiki->render_safe($content);

    # Generate slug from title
    my $slug = HSWiki::Wiki->slugify("My Page Title");  # "my-page-title"

    # Extract text preview
    my $preview = HSWiki::Wiki->preview($content, 100);

=head1 WIKI SYNTAX

    # Headers
    = Header 1 =
    == Header 2 ==
    ### Markdown-style headers work too

    # Emphasis
    '''bold text'''
    ''italic text''
    **bold** and *italic* markdown-style

    # Links
    [[PageName]]
    [[PageName|Display Text]]

    # Lists
    * Unordered item
    * Another item

    # Numbered list
    # First item
    # Second item

    # Code
    ```perl
    my $code = "example";
    ```

    # Auto-linked URLs
    https://example.com

=cut
