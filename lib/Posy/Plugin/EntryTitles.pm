package Posy::Plugin::EntryTitles;
use strict;

=head1 NAME

Posy::Plugin::EntryTitles - Posy plugin to cache entry titles

=head1 VERSION

This describes version B<0.40> of Posy::Plugin::EntryTitles.

=cut

our $VERSION = '0.40';

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

=head1 Configuration

The following config values can be set:

=over

=item B<titles_cachefile>

The full name of the file to be used to store the cache.
Most people can just leave this at the default.

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

    my $reindex = $self->param('reindex');
    $reindex = 1 if (!$self->_et_init_caching());
    if (!$reindex)
    {
	$reindex = 1 if (!$self->_et_read_cache());
    }
    # If any files are in $self->{files} but not in $self->{titles}, reindex
    for my $ffn (keys %{$self->{files}})
    { exists $self->{titles}->{$ffn}
	or do { $reindex++; delete $self->{titles}->{$ffn} }; }
    # If any files are in $self->{titles} but not in $self->{files}, reindex
    for my $ffn (keys %{$self->{titles}})
    { exists $self->{files}->{$ffn}
	or do { $reindex++; delete $self->{titles}->{$ffn} }; }

    if ($reindex) {
	foreach my $file_id (keys %{$self->{files}})
	{
	    $self->{titles}->{$file_id} = $self->get_title($file_id);
	}
	$self->_et_save_cache();
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
