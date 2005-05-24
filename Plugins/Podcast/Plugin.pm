# Podcast Browser v0.0
# Copyright (c) 2005 Slim Devices, Inc. (www.slimdevices.com)

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

package Plugins::Podcast::Plugin;
use strict;

use Slim::Utils::Misc;
use constant FEEDS_VERSION => 1;

use XML::Simple;

# default can be overridden by prefs.  See initPlugin()
# TODO: come up with a better list of defaults.
our @default_feeds = (
	{name => 'PodcastAlley Top 50',
	 value => 'http://podcastalley.com/PodcastAlleyTop50.opml'},
	{name => 'PodcastAlley 10 Newest',
	 value => 'http://podcastalley.com/PodcastAlley10Newest.opml'},
	# here's a nice list of radio programs.  Unfortunately the list is a little stale.  For instance all Air America links seem wrong.  Not sure yet whether it should be included in our defaults.
#	{name => 'Public Radio Feeds (Todd Maffin)',
#	 value => 'http://todmaffin.com/radio.opml'},
);

our @feeds = ();
our %feed_names; # cache of feed names

sub initPlugin {
	$::d_plugins && msg("Podcast Plugin initializing.\n");

	Slim::Buttons::Common::addMode('PLUGIN.Podcast', getFunctions(),
								   \&setMode);


	my @feedURLPrefs = Slim::Utils::Prefs::getArray("plugin_podcast_feeds");
	my @feedNamePrefs = Slim::Utils::Prefs::getArray("plugin_podcast_names");
	my $feedsModified = Slim::Utils::Prefs::get("plugin_podcast_feeds_modified");
	my $version = Slim::Utils::Prefs::get("plugin_podcast_feeds_version");

	@feeds = ();
	# No prefs set or we've had a version change and they weren't modified, 
	# so we'll use the defaults
	if (scalar(@feedURLPrefs) == 0 ||
		(!$feedsModified && (!$version  || $version != FEEDS_VERSION))) {
		# use defaults
		# set the prefs so the web interface will work.
		revertToDefaults();
	} else {
		# use prefs
		my $i = 0;
		while ($i < scalar(@feedNamePrefs)) {
			push @feeds, {name => $feedNamePrefs[$i],
						  value => $feedURLPrefs[$i]};
			$i++;
		}
	}

    if ($::d_plugins) {
        msg("Podcast Feed Info:\n");
        foreach (@feeds) {
            msg($_->{'name'} . ", " . $_->{'value'} . "\n");
        }
        msg("\n");
    }
	# feed_names should reflect current names
	%feed_names = ();
	map {$feed_names{$_->{'value'}} = $_->{'name'}} @feeds;
}

sub revertToDefaults {
	@feeds = @default_feeds;
	my @urls = map { $_->{'value'}} @feeds;
	my @names = map { $_->{'name'}} @feeds;
	Slim::Utils::Prefs::set('plugin_podcast_feeds', \@urls);
	Slim::Utils::Prefs::set('plugin_podcast_names', \@names);
	Slim::Utils::Prefs::set('plugin_podcast_feeds_version', FEEDS_VERSION);

	# feed_names should reflect current names
	%feed_names = ();
	map {$feed_names{$_->{'value'}} = $_->{'name'}} @feeds;
}

sub getDisplayName {
	return 'PLUGIN_PODCAST';
}

sub getFunctions {
	return {};
}

sub setMode {
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	# use INPUT.Choice to display the list of feeds
	my %params = (
		header => '{PLUGIN_PODCAST} {count}',
		listRef => \@feeds,
		modeName => 'Podcast Plugin',
		onRight => sub {
			my $client = shift;
			my $item = shift;
			my %params = (
				url => $item->{'value'},
				title => $item->{'name'},
			);
			Slim::Buttons::Common::pushModeLeft($client, 'podcastbrowser', \%params);
		},
		onPlay => sub {
			my $client = shift;
			my $item = shift;
			# url is also a playlist
			$client->execute(['playlist', 'play', $item->{'value'}, $item->{'name'}]);
		},
		onAdd => sub {
			my $client = shift;
			my $item = shift;
			# url is also a playlist
			$client->execute(['playlist', 'add', $item->{'value'}, $item->{'name'}]);
		},
		overlayRef => [undef,
					   Slim::Display::Display::symbol('notesymbol') .
					   Slim::Display::Display::symbol('rightarrow') ],
	);

	Slim::Buttons::Common::pushModeLeft($client, 'INPUT.Choice', \%params);
}

# this will undoubtably change.
# these are for testing more than anything else.
sub webPages {
	my %pages = (
		myPodcasts => sub {webPage('myPodcasts', @_)},
		myPodcasts2 => sub {webPage('myPodcasts2', @_)},
	);
	return \%pages;
}

sub webPage {
	my $page = shift;
	my $client = shift;
	my $params = shift;

	# TODO: set content type to XML
	return Slim::Web::HTTP::filltemplatefile("plugins/Podcast/$page",
											 $params);
}

# for configuring via web interface
sub setupGroup {
	my %Group = (
		PrefOrder => [
			'plugin_podcast_reset',
			'plugin_podcast_feeds',
		],
		GroupHead => Slim::Utils::Strings::string('PLUGIN_PODCAST'),
		GroupDesc => Slim::Utils::Strings::string('PODCAST_GROUP_DESC'),
		GroupLine => 1,
		GroupSub => 1,
		Suppress_PrefSub  => 1,
		Suppress_PrefLine => 1,
	);

	my %Prefs = (
		plugin_podcast_reset => {
			'validate' => \&Slim::Web::Setup::validateAcceptAll
			,'onChange' => sub {
				Slim::Utils::Prefs::set("plugin_podcast_feeds_modified", undef);
				Slim::Utils::Prefs::set("plugin_podcast_feeds_version", undef);
				revertToDefaults();
			}
			,'inputTemplate' => 'setup_input_submit.html'
			,'changeIntro' => Slim::Utils::Strings::string('PODCAST_RESETTING')
			,'ChangeButton' => Slim::Utils::Strings::string('PODCAST_RESET_BUTTON')
			,'dontSet' => 1
			,'changeMsg' => ''
		},
		plugin_podcast_feeds => {
			'isArray' => 1
			,'arrayAddExtra' => 1
			,'arrayDeleteNull' => 1
			,'arrayDeleteValue' => ''
			,'arrayBasicValue' => 0
			,'PrefSize' => 'large'
			,'inputTemplate' => 'setup_input_array_txt.html'
			,'PrefInTable' => 1
			,'showTextExtValue' => 1
			,'externalValue' => sub {
				my ($client, $value, $key) = @_;

				if ($key =~ /^(\D*)(\d+)$/ && ($2 < scalar(@feeds))) {
					return $feeds[$2]->{'name'};
				}

				return '';
			}
			,'onChange' => sub {
				my ($client,$changeref,$paramref,$pageref) = @_;
				if (exists($changeref->{'plugin_podcast_feeds'}{'Processed'})) {
					return;
				}
				Slim::Web::Setup::processArrayChange($client, 'plugin_podcast_feeds', $paramref, $pageref);
				updateFeedNames();

				$changeref->{'plugin_podcast_feeds'}{'Processed'} = 1;
			}
			,'changeMsg' => Slim::Utils::Strings::string('PODCAST_FEEDS_CHANGE')
		},
	);

	return( \%Group, \%Prefs );
}


sub updateFeedNames {
	my @feedURLPrefs = Slim::Utils::Prefs::getArray("plugin_podcast_feeds");
	my @feedNamePrefs;

	# verbose debug
	use Data::Dumper;
	msg("Podcast: updateFeedNames urls:\n");
	print Dumper(\@feedURLPrefs);

	# case 1: we're reverting to default
	if (scalar(@feedURLPrefs) == 0) {
		revertToDefaults();
	} else {
		# case 2: url list edited

		my $i = 0;
		while ($i < scalar(@feedURLPrefs)) {
			my $url = $feedURLPrefs[$i];
			my $name = $feed_names{$url};
			if ($name && $name !~ /^http\:/) {
				# no change
				$feedNamePrefs[$i] = $name;
			} elsif ($url =~ /^http\:/) {
				# does a synchronous get
				my $xml = getFeedXml($url);
				if ($xml && exists $xml->{channel}->{title}) {
					# here for podcasts and RSS
					$feedNamePrefs[$i] = Slim::Buttons::PodcastBrowser::unescapeAndTrim($xml->{channel}->{title});
				} elsif ($xml && exists $xml->{head}->{title}) {
					# here for OPML
					$feedNamePrefs[$i] = Slim::Buttons::PodcastBrowser::unescapeAndTrim($xml->{head}->{title});
				} else {
					# use url as title since we have nothing else
					$feedNamePrefs[$i] = $url;
				}
			} else {
				# use url as title since we have nothing else
				$feedNamePrefs[$i] = $url;
			}
			$i++;
		}

		# if names array contains more than urls, delete the extras
		while ($feedNamePrefs[$i]) {
			delete $feedNamePrefs[$i];
			$i++;
		}

		# save updated names to prefs
		Slim::Utils::Prefs::set('plugin_podcast_names', \@feedNamePrefs);

		# runtime list must reflect changes
		@feeds = ();
		$i = 0;
		while ($i < scalar(@feedNamePrefs)) {
			push @feeds, {name => $feedNamePrefs[$i],
						  value => $feedURLPrefs[$i]};
			$i++;
		}

		# feed_names should reflect current names
		%feed_names = ();
		map {$feed_names{$_->{'value'}} = $_->{'name'}} @feeds;
	}

}

# copied from RSS news plugin
# gets the xml for a feed synchronously
# only used to support the web interface
# when browsing, feeds are downloaded asynchronously, see PodcastBrowser.pm
sub getFeedXml {
    my $feed_url = shift;
    
    my $http = Slim::Player::Protocols::HTTP->new({
	'url'    => $feed_url,
	'create' => 0,
    });
    
    if (defined $http) {

	my $content = $http->content();

	$http->close();

	return 0 unless defined $content;

	# forcearray to treat items as array,
	# keyattr => [] prevents id attrs from overriding
        my $xml = eval { XMLin($content, forcearray => ["item"], keyattr => []) };

        if ($@) {
			$::d_plugins && msg("RssNews failed to parse feed <$feed_url> because:\n$@");
			return 0;
        }

        return $xml;
    }

    return 0;
}



sub strings { return q!
PLUGIN_PODCAST
	EN	Podcast Browser

PODCAST_ERROR
	DE	Fehler
	EN	Error

PODCAST_GET_FAILED
	DE	Fehler beim Auslesen
	EN	Failed to parse

PODCAST_LOADING
	DE	Hole Casts...
	EN	Fetching...

PODCAST_LINK
	EN	Link

PODCAST_URL
	EN	Url

PODCAST_DATE
	DE	Datum
	EN	Date

PODCAST_EDITOR
	DE	Herausgeber
	EN	Editor

PODCAST_ENCLOSURE
	EN	Enclosure

PODCAST_AUDIO_ENCLOSURES
	DE	Audio Enclosure
	EN	Audio Enclosures

PODCAST_NOTHING_TO_PLAY
	DE	Nichts zu spielen
	EN	Nothing to play

PODCAST_FEED_DESCRIPTION
	DE	Über diesen Podcast
	EN	About this podcast

PODCAST_GROUP_DESC
	DE	Der Podcast Browser erlaubt es, Podcasts anzusehen und abzuspielen.
	EN	The Podcast Browser plugin allows you to view and listen to podcasts.

PODCAST_RESET_BUTTON
	DE	Zurücksetzen
	EN	Reset

PODCAST_RESETTING
	DE	Setze Podcasts zurück
	EN	Resetting to default podcasts

PODCAST_FEEDS_CHANGE
	DE	Die Podcast Liste wurde geändert.
	EN	Podcast list changed.

SETUP_PLUGIN_PODCAST_FEEDS
	EN	Podcasts

SETUP_PLUGIN_PODCAST_RESET
	DE	Podcasts zurücksetzen
	EN	Reset default Podcasts


!};


1;
