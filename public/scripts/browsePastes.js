var consts= {
	CONTENT		: 0,
	DATE		: 1,
	ID		: 2,
	LINES		: 3,
	DEF_LINES	: 7
};

$(document).ready(function() {
	var href= window.location.href;
	$.get(href, getContent ); 
});	

function getContent(json) {
	var container= $('#content > div');

	var nav= container.children('p.bottomNav');
	// remove old click events
	nav.children().hide().off('click');

	if(json.error) {
		var notice= $('p.notice');
		notice.text(json.error).show();
		return false;
	}

	$('h1 span').text('Page ' + (json.page +1) + ' of '  + json.totalPages);
	$('.pastePreview').remove('div');
	$('.months div').empty();

	json.vals.forEach(function(e) {
		var link= '<a href="/pastes/' + e[consts.ID] + '" style="padding-right: 1em">';

		if(e[consts.LINES] > consts.DEF_LINES) {
			link+= 'View all</a> ' + e[consts.LINES] + ' lines';
		}
		else {
			link+= 'View</a> ';
		}
	container.append('<div class="pastePreview">'
		+'<p>'
		+'<span class="legendInList">' + link + "</span>"
		+'<span class="legendInList" style="float:right">' + e[consts.DATE] + '</span></p>'
		+'<pre>'
		+ e[consts.CONTENT]
		+ '</pre>\n</div>');

	});

	var mNames= ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', ];

	var years= json.index.years;
	var months= json.index.months;
	var url;

	years.forEach(function(e) {
		url= '/pastes/' + e + '/0/';

		addIndElem(e,url,0, e == json.year ? 1 : 0);
	});

	months.forEach(function(e) {
		url= '/pastes/' + json.year + '/'+ e +'/';

		addIndElem(mNames[e-1],url,1, e == json.month ? 1 : 0);
	});

	var prev= nav.children('a:eq(0)');
	var next= nav.children('a:eq(1)');


	url= '/pastes/'+json.year+'/'+json.month+'/';

	// move prev/next buttons below 
	nav.detach().appendTo(container);

	var page= json.page;
	if(page > 0) {
		prev.click(function() {
			$.get(url + (page -1), getContent );	
			return false;
		}).show();
	}

	if(page + 1 < json.totalPages) {
		next.click(function() {
			$.get(url + (page +1), getContent );	
			return false;
		}).show();
	}

	// try to change page url
	if (typeof (history.pushState) != "undefined") {
		var obj = { Title: '', Url: json.url };
		history.pushState(obj, obj.Title, obj.Url);
	}
}

function addIndElem(s, url, i, curr) {
		var e= $('<a></a>');
		if(curr) {
			e.toggleClass('selected');
		}

		e.text(s).attr('href',url).click(function () {
			$.get(url, getContent );	
			return false;
		}).appendTo('div .months > div:eq(' + i + ')');
}
