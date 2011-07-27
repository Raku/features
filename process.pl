use 5.010;
use strict;
use warnings;
use autodie;
use JSON;
use POSIX;
$ENV{TZ}='Z';

binmode(STDOUT, ":encoding(UTF-8)");

# read from 'features.json'
my $features = 'features.json';
my $mtime = (stat $features)[9];

# read in the json data
my $data;
{
    local $/;
    open my $f, '<:encoding(UTF-8)', $features;
    my $raw = <$f>;
    $data = decode_json($raw);
}


# place the column numbers for each compiler into %comp_index
my %comp_index;
my $comp_count = 0;
for my $c (@{$data->{'COMPILERS'}}) { 
    $comp_index{$c->{'abbr'}} = $comp_count++;
}

# walk through all of the items, filling in @ratings for each item 
# and populating footnotes
my %footnotes;
my $foot_count;
my %rating_class = ( 
    '+'  => 'implemented', 
    '-'  => 'missing',
    '+-' => 'partial',
    '?'  => 'unknown',
);
my %rating_text = ( '+-' => "\N{U+00B1}" );
for my $sec (@{$data->{'sections'}}) {
    for my $item (@{$sec->{'items'}}) {
        my $status = $item->{'status'};
        my @ratings;
        while ($status =~ m/(\w+)([+-]+)\s*(?:\(([^()]+)\))?/g) {
            my ($abbr, $rating, $comment) = ($1, $2, $3);
            die "Unknown abbreviation '$abbr'"
                unless exists $comp_index{$abbr};
            my $r = {
                status => $rating_text{$rating} // $rating,
                class  => $rating_class{$rating},
            };
            if ($comment) {
                $footnotes{$comment} //= ++$foot_count;
                $r->{footnote} = $footnotes{$comment};
                $r->{foottext} = $comment;
            }
            $ratings[$comp_index{$abbr}] = $r;
        }
        for (0..($comp_count-1)) {
            $ratings[$_] //= { status => '?', class => 'unknown' }
        }
        $item->{'ratings'} = \@ratings;
        $item->{'code'} = arrayify($item->{'code'}, 'code');
        $item->{'spec'} = arrayify($item->{'spec'}, 'spec');
    }
}

# use Data::Dumper;
# print Dumper $data;
write_html();

sub arrayify {
    my ($r, $key) = @_;
    if (defined $r && ref($r) eq 'ARRAY') {
        return [ map { { $key => $_ } } @{$r} ];
    }
    if ($r) {
        return [ { $key => $r } ];
    }
    [ ];
}


sub write_html {
    require HTML::Template::Compiled;
    my $t = HTML::Template::Compiled->new(
        filename        => 'template.html',
        open_mode       => ':encoding(UTF-8)',
        default_escape  => 'HTML',
        global_vars     => 1,
    );
    $t->param(compilers => $data->{'COMPILERS'});
    $t->param(sections  => $data->{'sections'});
    $t->param(when => POSIX::ctime($mtime) . " " . (POSIX::tzname())[0] );
    $t->param(now  => POSIX::ctime(time)   . " " . (POSIX::tzname())[0] );

    my @footkeys = sort { $footnotes{$a} <=> $footnotes{$b} } 
                        keys %footnotes;
    my @footnotes = map { { id => $footnotes{$_}, text => $_, } } @footkeys;
    $t->param(footnotes => \@footnotes);

    if (@ARGV) {
        my $filename = shift @ARGV;
        open my $out, '>:encoding(UTF-8)', $filename;
        print { $out } $t->output;
        close $out;
    } else {
        print $t->output;
    }
}
