import { Hono } from 'hono'
import { html } from 'hono/html'

const app = new Hono()

app.get('/', (c) => {
  return c.html(html`
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>My Personal Homepage</title>
      <script src="https://cdn.tailwindcss.com"></script>
    </head>
    <body class="bg-gray-900 text-white min-h-screen">
      <div class="container mx-auto px-4 py-16 max-w-4xl">
        <header class="text-center mb-12">
          <h1 class="text-5xl font-bold mb-4 text-blue-400">Hello, I'm a Builder!</h1>
          <p class="text-xl text-gray-300">Software Developer & OpenCode Student</p>
        </header>
        
        <section class="mb-12">
          <h2 class="text-3xl font-semibold mb-6 text-blue-300">About Me</h2>
          <div class="bg-gray-800 p-6 rounded-lg">
            <p class="text-gray-300 leading-relaxed">
              I'm a software developer who loves building things with code. 
              I primarily work in JavaScript/TypeScript and enjoy learning new technologies.
              Currently exploring AI-powered development tools and Cloudflare Workers.
            </p>
          </div>
        </section>
        
        <section class="mb-12">
          <h2 class="text-3xl font-semibold mb-6 text-blue-300">Interests</h2>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div class="bg-gray-800 p-4 rounded-lg">
              <h3 class="text-xl font-medium mb-2 text-blue-400">Web Development</h3>
              <p class="text-gray-400">Building modern web applications with React, TypeScript, and Cloudflare Workers</p>
            </div>
            <div class="bg-gray-800 p-4 rounded-lg">
              <h3 class="text-xl font-medium mb-2 text-blue-400">AI & Machine Learning</h3>
              <p class="text-gray-400">Exploring AI-powered development tools and machine learning models</p>
            </div>
            <div class="bg-gray-800 p-4 rounded-lg">
              <h3 class="text-xl font-medium mb-2 text-blue-400">Open Source</h3>
              <p class="text-gray-400">Contributing to open source projects and learning from the community</p>
            </div>
            <div class="bg-gray-800 p-4 rounded-lg">
              <h3 class="text-xl font-medium mb-2 text-blue-400">DevOps & Cloud</h3>
              <p class="text-gray-400">Deploying applications to the edge with Cloudflare and other cloud platforms</p>
            </div>
          </div>
        </section>
        
        <section class="mb-12">
          <h2 class="text-3xl font-semibold mb-6 text-blue-300">Connect</h2>
          <div class="flex flex-wrap justify-center gap-4">
            <a href="https://github.com" class="bg-gray-800 hover:bg-gray-700 px-6 py-3 rounded-lg transition-colors">
              GitHub
            </a>
            <a href="https://twitter.com" class="bg-gray-800 hover:bg-gray-700 px-6 py-3 rounded-lg transition-colors">
              Twitter
            </a>
            <a href="https://linkedin.com" class="bg-gray-800 hover:bg-gray-700 px-6 py-3 rounded-lg transition-colors">
              LinkedIn
            </a>
          </div>
        </section>
        
        <footer class="text-center text-gray-500 text-sm">
          <p>Built with Hono & Cloudflare Workers</p>
        </footer>
      </div>
    </body>
    </html>
  `)
})

export default app