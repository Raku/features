use 5.010;
use strict;
use warnings;
use autodie;


use Data::Dumper;
my $comment = qr{^\s*(?:\#.*)?$};

open my $f, '<:encoding(UTF-8)', 'features.txt';
binmode(STDOUT, ":encoding(UTF-8)");
my %abbr_name;
my %abbr_link;
my %abbr_index;
my $index = 0;
my $in_abbr_section;
my @sections;

while (<$f>) {
    chomp;
    next if $_ ~~ $comment;
    if (/^=\s+(.*)/) {
        my $title = $1;
        if ($title eq 'ABBREVIATIONS') {
            $in_abbr_section = 1;
        } else {
            $in_abbr_section = 0;
            push @sections, [$title];
        }
    }
    else {
        if ($in_abbr_section) {
            my ($abbr, $rest)  = split /\s+/, $_, 2;
            my ($name, $url)   = split /\s+(?=http)/, $rest, 2;
            $abbr_name{$abbr}  = $name;
            $abbr_link{$abbr}  = $url;
            $abbr_index{$abbr} = ++$index;
        }
        else {
            my ($name, $rest) = split /:\s*/, $_, 2;
            push @{$sections[-1]}, [$name];
            while ($rest =~ m/(\w+)([+-]+)\s*(?:\(([^()]+)\)\s*)?/g) {
                my ($abbr, $rating, $comment) = ($1, $2, $3);
                die "Unknown abbreviation '$abbr'"
                    unless exists $abbr_name{$abbr};
                my $i = $abbr_index{$abbr};
                die "Multiple data points for abbr '$abbr' at line $. -- possible typo?"
                    if $sections[-1][-1][$i];
                $rating = "\N{U+00B1}" if $rating eq "+-";
                $sections[-1][-1][$i] = [$rating, $comment];
            }
        }
    }
}

close $f;
write_html();

sub write_html {
    require HTML::Template::Compiled;
    my $t = HTML::Template::Compiled->new(
        filename        => 'template.html',
        open_mode       => ':encoding(UTF-8)',
        default_escape  => 'HTML',
        global_vars     => 1,
    );
    my @compilers;
    for (keys %abbr_index) {
        $compilers[$abbr_index{$_}] = {
            name => $abbr_name{$_},
            link => $abbr_link{$_},
        };
    }
    shift @compilers;
    $t->param(compilers => \@compilers);
    $t->param(columns   => 1 + @compilers);

    my %status_map = (
        '+'          => 'implemented',
        "\N{U+00B1}" => 'partial',
        '-'          => 'missing',
        '?'          => 'unknown',
    );

    my $footnote_counter = 0;
    my %footnotes;

    my @rows;
    for my $s (@sections) {
        my @sec = @$s;
        push @rows, {section => shift @sec};
        for (@sec) {
            my %ht_row;
            my @row = @$_;
            $ht_row{feature}  = shift @row;
            $ht_row{compilers} = [ map {
                my $h = {
                    status => $row[$_][0] // '?',
                    class  => $status_map{$row[$_][0] // '?'},
                };
                if (my $f = $row[$_][1]) {
                    $h->{footnote} = ($footnotes{$f} //= ++$footnote_counter);
                }
                $h;
            } 0..($index - 1) ];
            push @rows, \%ht_row;
        }
    }
    $t->param(rows => \@rows);

    {
        my @footnotes = sort { $footnotes{$a} <=> $footnotes{$b} }
                            keys %footnotes;
        my @f = map {
            {
                id   => $footnotes{$_},
                text => $_,
            }
        } @footnotes;
        $t->param(footnotes => \@f);
    }

    if (@ARGV) {
        my $filename = shift @ARGV;
        open my $out, '>:encoding(UTF-8)', $filename;
        print { $out } $t->output;
        close $out;
    } else {
        print $t->output;
    }
}
