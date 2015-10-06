$(document).ready(function() {
	$("#editor").submit(function(event) {
		var data= new Object();
		data.content= $('#pasteBody').val();
		data.lang= $('#langList').val();
		data.priv= $('#editor :checkbox[value="private"]').prop('checked');

		$.post('/pastes', data, function(json) {
			if(json.error) {
				var notice= $('p.notice');
				notice.text(json.error).show();

			}
			else {
				window.location= json.redirect;
			}
		}, 'json');
		return false;
	});
});	
