#!/usr/bin/env perl

use Mojolicious::Lite;
use lib 'lib';
use DBI_Wrapper;

our $VERSION= v0.2;

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

get '/:stat/:id' => [stat => 'private', id => qr/[-_A-Za-z0-9]{64}/] => \&viewPastes; 
get  '/:stat/:id' => [stat => 'pastes', id => qr/\d{1,10}/] =>  \&viewPastes;

sub viewPastes {
	my $c=  shift;
	my $id= $c->param('id');
	my $data;

	if($c->param('stat') eq 'private') {
		$data= $dbw->getPaste($id, 1);
	}
	else {
		$data= $dbw->getPaste($id);
	}


	if(defined $data and exists $data->{'error'}) {
		$c->flash(notice => $data->{'error'})
		->redirect_to('/');
	}

	$c->stash(paste => $data);

	$c->render(template => 'viewer');

};

post '/pastes' => sub { #ajax
	my $c = shift;
	my $pasteRef= \$c->req->param('content');
	my $lang= $c->req->param('lang');
	my $priv= $c->req->param('priv');

	#params are checked and untainted inside savePaste method
	$c->render(json => $dbw->savePaste($pasteRef, $lang, $priv));
};

app->start; 

__DATA__
@@ foo.html.ep

blah-blah
