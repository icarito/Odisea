// Hotzone upload worker
self.onmessage = async function(e) {
  var {url, token, blob, id} = e.data;
  try {
    var resp = await fetch(url, {
      method: 'POST',
      headers: {
        'Authorization': 'Bearer ' + token,
        'Content-Type': 'application/octet-stream'
      },
      body: blob
    });
    self.postMessage({id: id, ok: resp.ok, status: resp.status});
  } catch (err) {
    self.postMessage({id: id, ok: false, error: err.message});
  }
};
