#!/usr/bin/env perl

use Mojolicious::Lite;
use lib 'lib';
use DBI_Wrapper;
require bytes;

our $VERSION= v0.01;

use constant {
	PASTE_MESSAGE_SIZE => 75776,
	MAX_PASTE_SIZE => 65535
};

my $conf= plugin JSONConfig => {file => 'config.json'};
my $dbw= DBI_Wrapper->new($conf->{database});

app->defaults(layout => 'main');
app->defaults(langs => $dbw->getLangs);

hook after_build_tx => sub {
	my $tx = shift;

	return unless $tx->req->url->path->contains('/pastes');

	$tx->req->max_message_size(PASTE_MESSAGE_SIZE);
	
};


get '/' => sub {
  my $c = shift;

  $c->render(template => 'index');
};

post '/pastes' => sub {
	my $c = shift;
	my $pasteRef= \$c->req->body_params->param('paste[body]');
	my $langRef= \$c->req->body_params->param('paste[langList]');

	if (	bytes::length($$pasteRef) > MAX_PASTE_SIZE ) {
		$c->stash(notice => 'Paste cannot be larger than 64KB!');

	}
	else {
		my $lang= $dbw->langDefined($$langRef);
		$dbw->savePaste($pasteRef, $lang);
	}
	$c->render(template => 'foo', title => 'bar');
};

app->start; 

__DATA__
@@ foo.html.ep

blah-blah
