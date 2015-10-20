#!/usr/bin/env perl

use Mojolicious::Lite;
use lib 'lib';
use DBI_Wrapper;

our $VERSION= v0.25;

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

under '/pastes/';
	get '/' => \&browse; 

	# lowest available mon will be chosen, if mon == 0 
	get '/:year/:mon/:page' => [ year => qr/20\d{2}/, mon => qr/\d|1[0-2]/, page => qr/\d{0,4}/] =>\&browse;

	sub browse { 
		# normal or ajax
		# first get template with GET, then get content with AJAX
		my $c = shift;

		my $header= $c->req->headers->header('X-Requested-With');

		if((defined $header) and ($header eq 'XMLHttpRequest')) {
			
			$c->render( json => $dbw->getPaginatedPage(
					$c->param('year'),
					$c->param('mon'),
					$c->param('page')
				));
			return;
		}	

		$c->render(template => 'browser');
	};

	post '/' => sub { #ajax
		my $c = shift;
		my $pasteRef= \$c->req->param('content');
		my $lang= $c->req->param('lang');
		my $priv= $c->req->param('priv');

		# params are checked and untainted inside savePaste method
		$c->render(json => $dbw->savePaste($pasteRef, $lang, $priv));
	};
under '/';

app->start; 
