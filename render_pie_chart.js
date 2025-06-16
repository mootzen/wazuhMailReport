const { ChartJSNodeCanvas } = require('chartjs-node-canvas');
const fs = require('fs');

const width = 600;
const height = 600;
const chartJSNodeCanvas = new ChartJSNodeCanvas({ width, height });

const labels = process.argv[2].split(',');
const data = process.argv[3].split(',').map(Number);

const colors = [
  '#ff4c4c','#ff884c','#ffcc4c','#d0ff4c',
  '#4cff62','#4cffe1','#4ca7ff','#4c5cff','#a84cff','#ff4caa'
];

(async () => {
  const config = {
    type: 'pie',
    data: {
      labels: labels,
      datasets: [{
        label: 'Login Failures',
        data: data,
        backgroundColor: colors.slice(0, labels.length)
      }]
    },
    options: {
      plugins: {
        legend: { position: 'right' }
      }
    }
  };
  const image = await chartJSNodeCanvas.renderToBuffer(config);
  fs.writeFileSync('/tmp/login_chart.png', image);
})();
