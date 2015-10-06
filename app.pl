#!/usr/bin/env perl

use Mojolicious::Lite;
use lib 'lib';
use DBI_Wrapper;

our $VERSION= v0.02;

use constant {
	PASTE_MESSAGE_SIZE => 75776,
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

get  '/pastes/:id' => [id => qr/\d+/] => sub {
	my $c=  shift;
	my $id= $c->param('id');

	$c->render(text => $id, title => "#$id - paste");
};

post '/pastes' => sub { #ajax
	my $c = shift;
	my $pasteRef= \$c->req->param('content');
	my $lang= $c->req->param('lang');

	#params are checked and untainted inside savePaste method
	$c->render(json => $dbw->savePaste($pasteRef, $lang));
};

app->start; 

__DATA__
@@ foo.html.ep

blah-blah
