export default async function handler(req, res) {
  // CORS Headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.status(200).end();
    return;
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { id, type, sentiment, pin } = req.body;

  // Validate PIN
  const expectedPin = process.env.AUTH_PIN || '1234';
  if (pin !== expectedPin) {
    return res.status(401).json({ error: 'PIN incorrecto' });
  }

  // Validate GITHUB_TOKEN
  if (!process.env.GITHUB_TOKEN) {
    return res.status(500).json({ error: 'El GITHUB_TOKEN no está configurado en las variables de entorno de Vercel.' });
  }

  const owner = process.env.VERCEL_GIT_REPO_OWNER;
  const repo = process.env.VERCEL_GIT_REPO_SLUG;

  if (!owner || !repo) {
    return res.status(500).json({ error: 'No se pudo detectar el propietario o slug del repositorio Git. Asegúrate de que el proyecto esté vinculado a un repositorio Git en Vercel.' });
  }

  try {
    // 1. Get database.json
    const dbFile = await getFile('database.json', owner, repo);
    const db = JSON.parse(dbFile.content);

    let updated = false;
    const score = sentiment === 'positivo' ? 1.0 : (sentiment === 'negativo' ? -1.0 : 0.0);

    // Update the sentiment
    if (type === 'news') {
      const item = db.news.find(i => i.url === id);
      if (item) {
        item.sentiment = sentiment;
        item.sentiment_score = score;
        updated = true;
      }
    } else if (type === 'youtube') {
      const item = db.youtube.find(i => i.video_id === id);
      if (item) {
        item.sentiment = sentiment;
        item.sentiment_score = score;
        updated = true;
      }
    } else if (type === 'twitter') {
      const item = db.twitter.find(i => i.url === id);
      if (item) {
        item.sentiment = sentiment;
        item.sentiment_score = score;
        updated = true;
      }
    }

    if (!updated) {
      return res.status(404).json({ error: 'Item no encontrado' });
    }

    // 2. Prepare files
    const updatedDbContent = JSON.stringify(db, null, 2);

    const exportData = {
      news: db.news,
      youtube: db.youtube,
      twitter: db.twitter,
      updated_at: db.updated_at || new Date().toISOString().slice(0, 19)
    };
    const updatedDataJsonContent = JSON.stringify(exportData, null, 2);
    const updatedDataJsContent = `window.monitorData = ${JSON.stringify(exportData, null, 2)};`;

    // 3. Commit files
    const filesToCommit = [
      { path: 'database.json', content: updatedDbContent },
      { path: 'dashboard/data.json', content: updatedDataJsonContent },
      { path: 'dashboard/data.js', content: updatedDataJsContent }
    ];

    await commitMultipleFiles(filesToCommit, `chore: calificacion manual de post a ${sentiment} (${id})`, owner, repo);

    return res.status(200).json({ success: true });
  } catch (error) {
    console.error('Error handling update-sentiment:', error);
    return res.status(500).json({ error: error.message });
  }
}

async function getFile(path, owner, repo) {
  const url = `https://api.github.com/repos/${owner}/${repo}/contents/${path}`;
  const response = await fetch(url, {
    headers: {
      'Authorization': `token ${process.env.GITHUB_TOKEN}`,
      'Accept': 'application/vnd.github.v3+json',
      'User-Agent': 'MuniWatch-Dashboard'
    }
  });
  if (!response.ok) {
    throw new Error(`Failed to get file ${path}: ${response.statusText}`);
  }
  const data = await response.json();
  const content = Buffer.from(data.content, 'base64').toString('utf8');
  return { content, sha: data.sha };
}

async function commitMultipleFiles(files, commitMessage, owner, repo) {
  const token = process.env.GITHUB_TOKEN;
  const branch = 'main';
  const headers = {
    'Authorization': `token ${token}`,
    'Accept': 'application/vnd.github.v3+json',
    'User-Agent': 'MuniWatch-Dashboard',
    'Content-Type': 'application/json'
  };

  // Get ref
  const refRes = await fetch(`https://api.github.com/repos/${owner}/${repo}/git/ref/heads/${branch}`, { headers });
  if (!refRes.ok) throw new Error(`Failed to get branch ref: ${refRes.statusText}`);
  const refData = await refRes.json();
  const parentCommitSha = refData.object.sha;

  // Get commit
  const commitRes = await fetch(`https://api.github.com/repos/${owner}/${repo}/git/commits/${parentCommitSha}`, { headers });
  if (!commitRes.ok) throw new Error(`Failed to get parent commit: ${commitRes.statusText}`);
  const commitData = await commitRes.json();
  const parentTreeSha = commitData.tree.sha;

  // Create tree
  const treeItems = files.map(file => ({
    path: file.path,
    mode: '100644',
    type: 'blob',
    content: file.content
  }));

  const treeRes = await fetch(`https://api.github.com/repos/${owner}/${repo}/git/trees`, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      base_tree: parentTreeSha,
      tree: treeItems
    })
  });
  if (!treeRes.ok) throw new Error(`Failed to create tree: ${treeRes.statusText}`);
  const treeData = await treeRes.json();
  const newTreeSha = treeData.sha;

  // Create commit
  const newCommitRes = await fetch(`https://api.github.com/repos/${owner}/${repo}/git/commits`, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      message: commitMessage,
      tree: newTreeSha,
      parents: [parentCommitSha]
    })
  });
  if (!newCommitRes.ok) throw new Error(`Failed to create commit: ${newCommitRes.statusText}`);
  const newCommitData = await newCommitRes.json();
  const newCommitSha = newCommitData.sha;

  // Update ref
  const updateRefRes = await fetch(`https://api.github.com/repos/${owner}/${repo}/git/refs/heads/${branch}`, {
    method: 'PATCH',
    headers,
    body: JSON.stringify({
      sha: newCommitSha,
      force: false
    })
  });
  if (!updateRefRes.ok) throw new Error(`Failed to update ref: ${updateRefRes.statusText}`);
  return newCommitSha;
}
