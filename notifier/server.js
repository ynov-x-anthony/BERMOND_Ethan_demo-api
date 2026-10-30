const express = require('express');
const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3001;

app.get('/health', (req, res) => {
    res.status(200).json({ status: 'ok', service: 'notifier' });
});

app.post('/notify', (req, res) => {
    console.log('[NOTIFIER] Notification reçue :', JSON.stringify(req.body));
    res.status(200).json({ received: true });
});

app.listen(PORT, () => {
    console.log(`[NOTIFIER] Écoute sur le port ${PORT}`);
});