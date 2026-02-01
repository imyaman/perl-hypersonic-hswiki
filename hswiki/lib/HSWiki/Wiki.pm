package HSWiki::Wiki;

use strict;
use warnings;


use Text::WikiFormat ();
use HTML::Entities qw(encode_entities);

our $VERSION = '0.01';

# Render wiki markup to HTML
sub render {
    my ($class, $content, %opts) = @_;

    return '' unless defined $content;

    # Pre-process custom syntax before Text::WikiFormat
    $content = _preprocess($content, %opts);

    # Render with Text::WikiFormat using default settings
    my $html = Text::WikiFormat::format($content, {}, {
        extended       => 1,
        implicit_links => 0,
        absolute_links => 1,
    });

    # Post-process for additional features
    $html = _postprocess($html, %opts);

    return $html;
}

# Pre-process custom wiki syntax
sub _preprocess {
    my ($content, %opts) = @_;

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

    # Convert wiki links [[Page]] to regular links
    if ($opts{base_url}) {
        $content =~ s/\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/_format_link($1, $2, $opts{base_url})/ge;
    }

    return $content;
}

# Format wiki link
sub _format_link {
    my ($target, $text, $base_url) = @_;
    $text //= $target;
    my $slug = _slugify($target);
    $base_url //= '';
    return qq{<a href="$base_url/$slug">$text</a>};
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

    # Auto-link URLs (but not already linked ones)
    $html =~ s{(?<![">])(https?://[^\s<>"]+)}{<a href="$1" rel="nofollow">$1</a>}g;

    return $html;
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
