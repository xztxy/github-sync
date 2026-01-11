const simpleGit = require('simple-git');
const { Octokit } = require('@octokit/rest');
const fs = require('fs');
const path = require('path');

// 从环境变量获取配置
const sourceRepos = process.env.SOURCE_REPOS ? JSON.parse(process.env.SOURCE_REPOS) : [];
// 使用当前仓库作为目标仓库，GitHub Actions自动提供GITHUB_REPOSITORY环境变量
const targetRepo = process.env.TARGET_REPO || process.env.GITHUB_REPOSITORY;
const githubToken = process.env.GITHUB_TOKEN;

// 验证配置
if (!Array.isArray(sourceRepos) || sourceRepos.length === 0) {
  console.error('Error: SOURCE_REPOS must be a non-empty array');
  console.error('Please set SOURCE_REPOS environment variable with proper JSON format');
  process.exit(1);
}

if (!targetRepo || !githubToken) {
  console.error('Error: Missing required environment variables');
  if (!targetRepo) {
    console.error('  - TARGET_REPO: Not provided and GITHUB_REPOSITORY is not available (are you running in GitHub Actions?)');
  }
  if (!githubToken) {
    console.error('  - GITHUB_TOKEN: Please set this environment variable');
  }
  process.exit(1);
}

console.log('Starting repository sync...');
console.log(`Target Repo: ${targetRepo}`);
console.log(`Source Repos: ${JSON.stringify(sourceRepos)}`);

// 初始化 Octokit
const octokit = new Octokit({
  auth: githubToken
});

// 主同步函数
const syncRepositories = async () => {
  try {
    // 遍历每个源仓库
    for (const repoConfig of sourceRepos) {
      const {
        repoUrl,
        sourceBranch = 'main',
        targetBranch = path.basename(repoUrl, '.git'),
        repoName = path.basename(repoUrl, '.git')
      } = repoConfig;

      console.log(`\n🔄 Processing repository: ${repoName}`);
      console.log(`   Source: ${repoUrl} (${sourceBranch})`);
      console.log(`   Target: ${targetRepo} (${targetBranch})`);

      // 为每个仓库创建独立的临时目录
      const tempDir = path.join(__dirname, 'temp', repoName);
      
      // 确保临时目录存在
      if (!fs.existsSync(tempDir)) {
        fs.mkdirSync(tempDir, { recursive: true });
      }

      // 克隆源仓库
      console.log(`   Cloning repository: ${repoUrl}`);
      const git = simpleGit();
      await git.clone(repoUrl, tempDir, {
        '--single-branch': true,
        '--branch': sourceBranch,
        '--depth': 1
      });

      const repoGit = simpleGit(tempDir);

      // 拉取最新代码
      await repoGit.pull('origin', sourceBranch);

      // 推送代码到目标仓库的目标分支
      const targetUrl = `https://x-access-token:${githubToken}@github.com/${targetRepo}.git`;
      await repoGit.push(targetUrl, `${sourceBranch}:${targetBranch}`, {
        '--force': true
      });

      console.log(`   ✅ Successfully synced ${repoName}: ${sourceBranch} -> ${targetBranch}`);

      // 清理当前仓库的临时目录
      if (fs.existsSync(tempDir)) {
        fs.rmSync(tempDir, { recursive: true, force: true });
      }
    }
    
    console.log('\n✅ All repositories synced successfully!');
    
  } catch (error) {
    console.error('❌ Sync failed:', error.message);
    console.error(error.stack);
    process.exit(1);
  } finally {
    // 清理主临时目录
    const mainTempDir = path.join(__dirname, 'temp');
    if (fs.existsSync(mainTempDir)) {
      fs.rmSync(mainTempDir, { recursive: true, force: true });
      console.log('Cleaned up main temp directory');
    }
  }
};

// 运行同步
syncRepositories();
