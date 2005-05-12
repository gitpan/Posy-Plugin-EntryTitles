package Posy::Plugin::EntryTitles;
use strict;

=head1 NAME

Posy::Plugin::EntryTitles - Posy plugin to cache entry titles.

=head1 VERSION

This describes version B<0.51> of Posy::Plugin::EntryTitles.

=cut

our $VERSION = '0.51';

=head1 SYNOPSIS

    @plugins = qw(Posy::Core
		  Posy::Plugin::EntryTitles
		  ...
		  ));
    @actions = qw(
	....
	index_entries
	index_titles
	...
	);

=head1 DESCRIPTION

This is a "utility" plugin to be used by other plugins; it maintains
a list (and cache) of entry titles in $self->{titles} which can
be used by other plugins (such as Posy::Plugin::NearLinks).

It provides an action method L</index_titles> which should be put
after "index_entries" in the action list.

This plugin is useful not only for efficiency reasons, but it means that
other plugins don't have to know how to extract the title from a given
format of file; the title for a HTML file, for example, is not parsed in
the same way as that for a plain text file.  Those who wish to introduce
additional formats need only override the L</get_title> method and 
everything will work just as smoothly.  Ah, inheritance, I love it.

=head2 Configuration

The following config values can be set:

=over

=item B<titles_cachefile>

The full name of the file to be used to store the cache.
Most people can just leave this at the default.

=back

=head2 Parameters

This plugin will do reindexing the first time it is run, or
if it detects that there are files in the main file index which
are new.  Full or partial reindexing can be forced by setting the
the following parameters:

=over

=item reindex_all

    /cgi-bin/posy.cgi?reindex_all=1

Does a full reindex of all files in the data_dir directory,
clearing the existing information and starting again.

=item reindex

    /cgi-bin/posy.cgi?reindex=1

Updates information for new files only.

=item reindex_cat

    /cgi-bin/posy.cgi?reindex_cat=stories/buffy

Does an additive reindex of all files under the given category.  Does not
delete files from the index.  Useful to call when you know you've just
updated/added files in a particular category index, and don't want to have
to reindex the whole site.

=item delindex

    /cgi-bin/posy.cgi?delindex=1

Deletes files from the index if they no longer exist.  Useful when you've
deleted files but don't want to have to reindex the whole site.

=back

=cut

=head1 OBJECT METHODS

Documentation for developers and those wishing to write plugins.

=head2 init

Do some initialization; make sure that default config values are set.

=cut
sub init {
    my $self = shift;
    $self->SUPER::init();

    # set defaults
    $self->{config}->{titles_cachefile} ||=
	File::Spec->catfile($self->{state_dir}, 'titles.dat');
} # init


=head1 Flow Action Methods

Methods implementing actions.

=head2 index_titles

Find the titles of the entry files.
This uses caching by default.

Expects $self->{config}
and $self->{files} to be set.

=cut

sub index_titles {
    my $self = shift;
    my $flow_state = shift;

    my $reindex_all = $self->param('reindex_all');
    $reindex_all = 1 if (!$self->_et_init_caching());
    if (!$reindex_all)
    {
	$reindex_all = 1 if (!$self->_et_read_cache());
    }
    # check for a partial reindex
    my $reindex_cat = $self->param('reindex_cat');
    # make sure there's no extraneous slashes
    $reindex_cat =~ s{^/}{};
    $reindex_cat =~ s{/$}{};
    if (!$reindex_all
	and $reindex_cat
	and exists $self->{categories}->{$reindex_cat}
	and defined $self->{categories}->{$reindex_cat})
    {
	$self->debug(1, "EntryTitles: reindexing $reindex_cat");
	while (my $file_id = each %{$self->{files}})
	{
	    if (($self->{files}->{$file_id}->{cat_id} eq $reindex_cat)
		or ($self->{files}->{$file_id}->{cat_id}
		    =~ /^$reindex_cat/)
	       )
	    {
		$self->{titles}->{$file_id} = $self->get_title($file_id);
	    }
	}
	$self->_et_save_cache();
    }
    elsif (!$reindex_all)
    {
	# If any files are in $self->{files} but not in $self->{titles}
	# add them to the index
	my $newfiles = 0;
	while (my $file_id = each %{$self->{files}})
	{ exists $self->{titles}->{$file_id}
	    or do {
		$newfiles++;
		$self->{titles}->{$file_id} = $self->get_title($file_id);
	    };
	}
	$self->debug(1, "EntryTitles: added $newfiles new files") if $newfiles;
	$self->_et_save_cache() if $newfiles;
    }

    if ($reindex_all) {
	$self->debug(1, "EntryTitles: reindexing ALL");
	while (my $file_id = each %{$self->{files}})
	{
	    $self->{titles}->{$file_id} = $self->get_title($file_id);
	}
	$self->_et_save_cache();
    }
    else
    {
	# If any files not available, delete them and just save the cache
	if ($self->param('delindex'))
	{
	    $self->debug(1, "EntryTitles: checking for deleted files");
	    my $deletions = 0;
	    while (my $key = each %{$self->{titles}})
	    { exists $self->{files}->{$key}
		or do { $deletions++; delete $self->{titles}->{$key} };
	    }
	    $self->debug(1, "EntryTitles: deleted $deletions gone files")
		if $deletions;
	    $self->_et_save_cache() if $deletions;
	}
    }
} # index_titles

=head1 Helper Methods

Methods which can be called from elsewhere.

=head2 get_title

    $title = $self->get_title($file_id);

Get the title of the given entry file (by reading the file).
(If you are introducing a new file-type, you should override this)

=cut
sub get_title {
    my $self = shift;
    my $file_id = shift;

    my $fullname = $self->{files}->{$file_id}->{fullname};
    my $ext = $self->{files}->{$file_id}->{ext};
    my $file_type = $self->{file_extensions}->{$ext};
    my $title = '';
    my $fh;
    if ($file_type eq 'html')
    {
	local $/;
	open($fh, $fullname) or return "Could not open $fullname";
	my $html = <$fh>;
	if ($html =~ m#<title>([^>]+)</title>#sio)
	{
	    $title = $1;
	}
	close($fh);
    }
    else # Text or BLX -- use the first line
    {
	open($fh, $fullname) or return "Could not open $fullname";
	$title = <$fh>;
	close($fh);
    }
    $title = $self->{files}->{$file_id}->{basename} if (!$title);
    $self->debug(2, "$file_id title=$title");
    return $title;
} # get_title

=head1 Private Methods

Methods which may or may not be here in future.

=head2 _et_init_caching

Initialize the caching stuff used by index_entries

=cut
sub _et_init_caching {
    my $self = shift;

    return 0 if (!$self->{config}->{use_caching});
    eval "require Storable";
    if ($@) {
	$self->debug(1, "EntryTitles: cache disabled, Storable not available"); 
	$self->{config}->{use_caching} = 0; 
	return 0;
    }
    if (!Storable->can('lock_retrieve')) {
	$self->debug(1, "EntryTitles: cache disabled, Storable::lock_retrieve not available");
	$self->{config}->{use_caching} = 0;
	return 0;
    }
    $self->debug(1, "EntryTitles: using caching");
    return 1;
} # _et_init_caching

=head2 _et_read_cache

Reads the cached information used by index_entries

=cut
sub _et_read_cache {
    my $self = shift;

    return 0 if (!$self->{config}->{use_caching});
    $self->{titles} = (-r $self->{config}->{titles_cachefile}
	? Storable::lock_retrieve($self->{config}->{titles_cachefile}) : undef);
    if ($self->{titles}) {
	$self->debug(1, "EntryTitles: Using cached state");
	return 1;
    }
    $self->{titles} = {};
    $self->debug(1, "EntryTitles: Flushing caches");
    return 0;
} # _et_read_cache

=head2 _et_save_cache

Saved the information gathered by index_entries to caches.

=cut
sub _et_save_cache {
    my $self = shift;
    return if (!$self->{config}->{use_caching});
    $self->debug(1, "EntryTitles: Saving caches");
    Storable::lock_store($self->{titles}, $self->{config}->{titles_cachefile});
} # _et_save_cache

=head1 INSTALLATION

Installation needs will vary depending on the particular setup a person
has.

=head2 Administrator, Automatic

If you are the administrator of the system, then the dead simple method of
installing the modules is to use the CPAN or CPANPLUS system.

    cpanp -i Posy::Plugin::EntryTitles

This will install this plugin in the usual places where modules get
installed when one is using CPAN(PLUS).

=head2 Administrator, By Hand

If you are the administrator of the system, but don't wish to use the
CPAN(PLUS) method, then this is for you.  Take the *.tar.gz file
and untar it in a suitable directory.

To install this module, run the following commands:

    perl Build.PL
    ./Build
    ./Build test
    ./Build install

Or, if you're on a platform (like DOS or Windows) that doesn't like the
"./" notation, you can do this:

   perl Build.PL
   perl Build
   perl Build test
   perl Build install

=head2 User With Shell Access

If you are a user on a system, and don't have root/administrator access,
you need to install Posy somewhere other than the default place (since you
don't have access to it).  However, if you have shell access to the system,
then you can install it in your home directory.

Say your home directory is "/home/fred", and you want to install the
modules into a subdirectory called "perl".

Download the *.tar.gz file and untar it in a suitable directory.

    perl Build.PL --install_base /home/fred/perl
    ./Build
    ./Build test
    ./Build install

This will install the files underneath /home/fred/perl.

You will then need to make sure that you alter the PERL5LIB variable to
find the modules, and the PATH variable to find the scripts (posy_one,
posy_static).

Therefore you will need to change:
your path, to include /home/fred/perl/script (where the script will be)

	PATH=/home/fred/perl/script:${PATH}

the PERL5LIB variable to add /home/fred/perl/lib

	PERL5LIB=/home/fred/perl/lib:${PERL5LIB}

=head1 REQUIRES

    Posy
    Posy::Core

    Test::More

=head1 SEE ALSO

perl(1).
Posy
Posy::Plugin::TextTemplate
Posy::Plugin::NearLinks

=head1 BUGS

Please report any bugs or feature requests to the author.

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    perlkat AT katspace dot com
    http://www.katspace.com

=head1 COPYRIGHT AND LICENCE

Copyright (c) 2004-2005 by Kathryn Andersen

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of Posy::Plugin::EntryTitles
__END__
