use strict;
use warnings;

package Toolbox::FileSystem;

# ABSTRACT: common filesystem-y things
our $VERSION = 'v1.0.7';

##~ DIGEST : be996065b414fe8f80510b77b59f6094
use Carp qw/ cluck confess /;

our $TEMPDIR;
use Exporter qw(import);
our @EXPORT_OK = qw(
  checkpath
  checkfile
  checkdir
  subonfiles
  filebasename
  mvf
  safemvf
  cpf
  abspath
  mkpath
  safeduplicatepath
  thisfile
  tempdir
);

=head3 checkpath
	Given a path and optionally the 'context name' of the variable that connects it, confirm presence or HCF
=cut

sub checkpath {
	my ( $path, $value_name ) = @_;
	$value_name = _value_name( $value_name );
	confess( "checkpath $value_name value is null" ) unless $path;
	confess( "checkpath $value_name path [$path] does not exist" ) unless -e $path;
	return 1;

}

sub checkfile {
	my ( $path, $value_name ) = @_;
	$value_name = _value_name( $value_name );
	checkpath( $path, $value_name );
	confess( "checkfile $value_name path [$path] is not a file " ) unless -f $path;
}

sub checkdir {
	my ( $path, $value_name ) = @_;
	$value_name = _value_name( $value_name );
	checkpath( $path, $value_name );
	confess( "checkdir $value_name path [$path] is not a directory " ) unless -d $path;

}

sub filebasename {
	my ( $path ) = @_;
	die "wrong method name";

	# 	require File::Spec;
	# 	my ( $dev, $dir, $file ) = File::Spec->splitpath( $path );
	# 	return ( $file, $dir, $dev );

}

sub filepathparts {
	my ( $path ) = @_;
	require File::Spec;
	my ( $dev, $dir, $file ) = File::Spec->splitpath( $path );
	return ( $file, $dir, $dev );
}

sub _value_name {
	my ( $value_name ) = @_;
	unless ( $value_name ) {
		$value_name = '';
	}
	return $value_name;
}

sub mvf {

	my ( $source, $target ) = _shared_fc( @_ );

	require File::Copy;
	File::Copy::mv( $source, $target ) or confess( "move failed: $!" );

}

=head3 safemvf
	Move a file or else - in that it'll try and do everything what needs doing otherwise
=cut 

sub safemvf {

	my ( $source, $target ) = _shared_fc( @_ );

	#HCF if we're trying to move nothing
	checkfile( $source );
	my $target_dir;

	require File::Basename;

	#Handle moving a file to a directory without an explicit file name
	if ( -d $target ) {
		my ( $name, $dir ) = File::Basename::fileparse( $source );
		$target = "$target/$name";
	} else {

		my ( $name, $target_dir ) = File::Basename::fileparse( $target );

		#does nothing if target directory exists already
		mkpath( $target_dir );
		$target = "$target_dir/$name";
	}

	#HFC if we're trying to overwrite
	safeduplicatepath( $target, {fatal => 1} );

	require File::Copy;
	File::Copy::mv( $source, $target_dir || $target )
	  or confess( "move failed: $!" );
	return 1;
}

sub safeduplicatepath {
	my ( $path, $c ) = @_;

	$c ||= {};
	if ( -e $path ) {
		confess( "Target [$path] already exists" ) if $c->{fatal};
		require File::Basename;
		my ( $name, $dir, $suffix ) = File::Basename::fileparse( $path, qr/\.[^.]*/ );
		require Data::UUID;
		my $ug   = Data::UUID->new;
		my $uuid = $ug->to_string( $ug->create() );

		# TODO sprintf?
		my $newpath = "$dir/$name\_$uuid$suffix";

		cluck( "Target [$path] already exists, renamed to $newpath" )
		  unless $c->{mute};

		return $newpath;
	}
	return $path;

}

sub tempdir {
	unless ( $TEMPDIR ) {
		my ( $root ) = @_;
		$root ||= './';
		$root    = abspath( $root );
		$TEMPDIR = buildtimepath( $root );
		mkpath( $TEMPDIR );
	}

	return $TEMPDIR;

}

sub buildtimepath {
	my ( $root ) = @_;
	checkdir( $root );
	require Data::UUID;
	require POSIX;
	my $ug      = Data::UUID->new;
	my $uuid    = lc( $ug->create_str() );
	my $tmppath = POSIX::strftime( "/%Y-%m-%d/%H/%M:%S/", gmtime() );
	return abspath( "$root/$tmppath/$uuid/" );
}

sub cpf {
	my ( $source, $target ) = _shared_fc( @_ );
	require File::Copy;
	File::Copy::cp( $source, $target ) or confess( "copy failed: $!" );
}

=head3 mkpath
	make a directory path or die trying
=cut

sub mkpath {
	my ( $path ) = @_;
	confess( "Path missing" ) unless $path;
	return $path if -d $path;
	require File::Path;
	my $errors;
	File::Path::make_path( $path, {error => \$errors} );
	if ( $errors && @{$errors} ) {
		my $errstr;
		for ( @{$errors} ) {
			$errstr .= $_ . $/;
		}
		confess( "[$path] creation failed : [$/$errstr]$/" );
	}

	#for when it's coming in as a string concat and the result is useful as a variable
	return $path;

}

sub _shared_fc {
	my ( $source, $target ) = @_;
	$source = abspath( $source );
	$target = abspath( $target );
	return ( $source, $target );
}

sub abspath {

	my ( $path ) = @_;
	my $return;
	if ( -e $path ) {
		require Cwd;
		$return = Cwd::abs_path( $path );
		if ( -d $return ) {
			$return .= '/';
		}
	} else {
		require File::Spec;
		$return = File::Spec->rel2abs( $path );
	}
	return $return; #return!

}

sub subonfiles {
	my ( $sub, $dir ) = @_;
	require File::Find::Rule;
	confess( "First parameter to subonfiles was not a code reference" )
	  unless ref( $sub ) eq 'CODE';
	checkdir( $dir, 'subonfiles directory' );
	my @files = File::Find::Rule->file()->in( $dir );
	my $stop;
	for ( @files ) {
		$stop = &$sub( abspath( $_ ) );
		last if $stop;
	}
}

#identical to the above but assumes a true return from the sub means keep going
# TODO go through files as they come instead of all at once
sub sub_on_files {
	my ( $sub, $dir ) = @_;
	require File::Find;

	confess( "First parameter to subonfiles was not a code reference" ) unless ref( $sub ) eq 'CODE';
	checkdir( $dir, 'subonfiles directory' );
	my @files = File::Find::Rule->file()->in( $dir );
	my $stop;
	for ( @files ) {
		last unless &$sub( abspath( $_ ) );
	}
}

1;
