#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use lib 'lib';

# Check if Text::WikiFormat is available
eval { require Text::WikiFormat };
if ($@) {
    plan skip_all => 'Text::WikiFormat not installed';
} else {
    plan tests => 12;
}

use_ok('HSWiki::Wiki');

# Test slugify
is(HSWiki::Wiki->slugify('Hello World'), 'hello-world', 'Basic slugify');
is(HSWiki::Wiki->slugify('Test Page 123'), 'test-page-123', 'Slugify with numbers');
is(HSWiki::Wiki->slugify('Special!@#Characters'), 'specialcharacters', 'Slugify removes special chars');

# Test basic rendering
my $simple = "Hello World";
my $html = HSWiki::Wiki->render($simple);
ok($html, 'Basic render produces output');

# Test header rendering
my $header = "= Header 1 =";
my $header_html = HSWiki::Wiki->render($header);
like($header_html, qr/<h/, 'Header renders to h tag');

# Test bold (using wiki syntax)
my $bold = "'''bold text'''";
my $bold_html = HSWiki::Wiki->render($bold);
like($bold_html, qr/<strong>|<b>/, 'Bold renders to strong/b tag');

# Test that basic text is rendered
my $text = "This is a paragraph.";
my $text_html = HSWiki::Wiki->render($text);
like($text_html, qr/This is a paragraph/, 'Text content preserved');

# Test code blocks
my $code = "```perl\nmy \$x = 1;\n```";
my $code_html = HSWiki::Wiki->render($code);
like($code_html, qr/<pre>|<code>/, 'Code blocks render');

# Test preview
my $long_content = "This is a long piece of content " x 20;
my $preview = HSWiki::Wiki->preview($long_content, 50);
ok(length($preview) <= 53, 'Preview truncates properly');  # 50 + ...

# Test sanitization
my $unsafe = '<script>alert("xss")</script>Normal text';
my $safe = HSWiki::Wiki->sanitize_html($unsafe);
unlike($safe, qr/<script>/, 'Script tags removed');
like($safe, qr/Normal text/, 'Safe text preserved');

done_testing();
