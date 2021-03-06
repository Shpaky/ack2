#!perl -T

use strict;
use warnings;

use File::Spec ();
use File::Temp ();
use Test::More;
use lib 't';
use Util;

prep_environment();

my @tests = (
    [ qw/Sue/ ],
    [ qw/boy -i/ ], # case-insensitive is handled correctly with --match
    [ qw/ll+ -Q/ ], # quotemeta        is handled correctly with --match
    [ qw/gon -w/ ], # words            is handled correctly with --match
);

plan tests => @tests + 11;

test_match( @{$_} ) for @tests;

# Giving only the --match argument (and no other args) should not result in an error.
run_ack( '--match', 'Sue' );

# Not giving a regex when piping into ack should result in an error.
my ($stdout, $stderr) = pipe_into_ack_with_stderr( 't/text/amontillado.txt', '--perl' );
isnt( get_rc(), 0, 'ack should return an error when piped into without a regex' );
is_empty_array( $stdout, 'ack should return no STDOUT when piped into without a regex' );
cmp_ok( scalar @{$stderr}, '>', 0, 'Has to have at least one line of error message, but could have more under Appveyor' );

my $name = $ENV{ACK_TEST_STANDALONE} ? 'ack-standalone' : 'ack';
is( $stderr->[0], "$name: No regular expression found.", 'Error message matches' );

my $wd      = getcwd_clean();
my $tempdir = File::Temp->newdir;
safe_mkdir( File::Spec->catdir($tempdir->dirname, 'subdir') );

PROJECT_ACKRC_MATCH_FORBIDDEN: {
    my @files = untaint( File::Spec->rel2abs('t/text/') );
    my @args = qw/ --env /;

    safe_chdir( $tempdir->dirname );
    write_file '.ackrc', "--match=question\n";

    my ( $stdout, $stderr ) = run_ack_with_stderr(@args, @files);

    is_empty_array( $stdout );
    first_line_like( $stderr, qr/\QOptions --output, --pager and --match are forbidden in project .ackrc files/ );

    safe_chdir( $wd );
}

HOME_ACKRC_MATCH_PERMITTED: {
    my @files = untaint( File::Spec->rel2abs('t/text/') );
    my @args = qw/ --env /;

    write_file(File::Spec->catfile($tempdir->dirname, '.ackrc'), "--match=question\n");
    safe_chdir( File::Spec->catdir($tempdir->dirname, 'subdir') );
    local $ENV{'HOME'} = $tempdir->dirname;

    my ( $stdout, $stderr ) = run_ack_with_stderr(@args, @files);

    is_nonempty_array( $stdout );
    is_empty_array( $stderr );

    safe_chdir( $wd );
}

ACKRC_ACKRC_MATCH_PERMITTED: {
    my @files = untaint( File::Spec->rel2abs('t/text/') );
    my @args = qw/ --env /;

    write_file(File::Spec->catfile($tempdir->dirname, '.ackrc'), "--match=question\n");
    safe_chdir( File::Spec->catdir($tempdir->dirname, 'subdir') );
    local $ENV{'ACKRC'} = File::Spec->catfile($tempdir->dirname, '.ackrc');

    my ( $stdout, $stderr ) = run_ack_with_stderr(@args, @files);

    is_nonempty_array( $stdout );
    is_empty_array( $stderr );

    safe_chdir( $wd );
}
done_testing;

# Call ack normally and compare output to calling with --match regex.
#
# Due to 2 calls to run_ack, this sub runs altogether 3 tests.
sub test_match {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $regex = shift;
    my @args  = @_;
    push @args, '--sort-files';

    return subtest "test_match( @args )" => sub {
        my @files = ( 't/text' );
        my @results_normal = run_ack( @args, $regex, @files );
        my @results_match  = run_ack( @args, @files, '--match', $regex );

        return sets_match( \@results_normal, \@results_match, "Same output for regex '$regex'." );
    };
}
