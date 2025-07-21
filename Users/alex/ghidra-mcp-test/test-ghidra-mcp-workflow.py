#!/usr/bin/env python
"""
🧪 Ghidra + MCP + DyldExtractor Test Workflow
==============================================

This script demonstrates the complete workflow for macOS reverse engineering
using Ghidra with MCP (Model Context Protocol) integration and DyldExtractor.

Prerequisites:
- Run this from within `nix develop` environment
- MCP bridge should be set up with `setup-mcp-bridge`
- Frameworks should be extracted with `dyldex`

Usage:
    python test-ghidra-mcp-workflow.py
"""

import os
import sys
import subprocess
import json
from pathlib import Path

class GhidraMCPTester:
    def __init__(self):
        self.test_dir = Path.cwd()
        self.frameworks_dir = self.test_dir / "frameworks"
        self.ghidra_projects_dir = self.test_dir / "ghidra-projects"
        self.mcp_plugin_path = self.test_dir / "GhidraMCP" / "target" / "GhidraMCP-1.0-SNAPSHOT.zip"
        
    def check_prerequisites(self):
        """Check if all prerequisites are met"""
        print("🔍 Checking prerequisites...")
        
        checks = [
            ("Ghidra available", self._check_ghidra()),
            ("MCP plugin built", self.mcp_plugin_path.exists()),
            ("Frameworks extracted", self.frameworks_dir.exists() and list(self.frameworks_dir.glob("*"))),
            ("DyldExtractor available", self._check_dyldex()),
        ]
        
        all_good = True
        for check_name, result in checks:
            status = "✅" if result else "❌"
            print(f"  {status} {check_name}")
            if not result:
                all_good = False
                
        return all_good
    
    def _check_ghidra(self):
        """Check if Ghidra is available"""
        try:
            result = subprocess.run(["which", "ghidra"], capture_output=True, text=True)
            return result.returncode == 0
        except:
            return False
    
    def _check_dyldex(self):
        """Check if dyldex is available"""
        try:
            result = subprocess.run(["which", "dyldex"], capture_output=True, text=True)
            return result.returncode == 0
        except:
            return False
    
    def list_available_frameworks(self):
        """List available frameworks for analysis"""
        print("\n📁 Available frameworks for analysis:")
        if not self.frameworks_dir.exists():
            print("  No frameworks directory found")
            return []
            
        frameworks = list(self.frameworks_dir.glob("*"))
        if not frameworks:
            print("  No frameworks extracted")
            return []
            
        for fw in frameworks:
            size = fw.stat().st_size / (1024 * 1024)  # MB
            print(f"  📦 {fw.name} ({size:.1f} MB)")
            
        return frameworks
    
    def analyze_framework_with_file_command(self, framework_path):
        """Analyze framework using file command"""
        print(f"\n🔍 Analyzing {framework_path.name} with file command:")
        try:
            result = subprocess.run(["file", str(framework_path)], capture_output=True, text=True)
            print(f"  {result.stdout.strip()}")
        except Exception as e:
            print(f"  Error: {e}")
    
    def extract_strings_sample(self, framework_path, limit=10):
        """Extract sample strings from framework"""
        print(f"\n🔤 Sample strings from {framework_path.name}:")
        try:
            result = subprocess.run(
                ["strings", str(framework_path)], 
                capture_output=True, text=True
            )
            strings = result.stdout.strip().split('\n')
            interesting_strings = [s for s in strings if len(s) > 10 and any(keyword in s.lower() for keyword in ['class', 'method', 'function', 'error', 'debug'])]
            
            for i, string in enumerate(interesting_strings[:limit]):
                print(f"  {i+1:2d}. {string}")
                
        except Exception as e:
            print(f"  Error: {e}")
    
    def create_ghidra_project_script(self):
        """Create a Ghidra script for automated analysis"""
        script_content = '''
// Ghidra MCP Test Script
// @category MCP
// @description Test script for MCP integration

import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.*;

public class MCPTestScript extends GhidraScript {
    
    @Override
    public void run() throws Exception {
        println("🚀 Starting MCP Test Analysis...");
        
        Program program = getCurrentProgram();
        if (program == null) {
            println("❌ No program loaded");
            return;
        }
        
        println("📊 Program: " + program.getName());
        println("🏗️  Architecture: " + program.getLanguage().getProcessor());
        println("📏 Address Space: " + program.getAddressFactory().getDefaultAddressSpace());
        
        // Count functions
        FunctionManager funcMgr = program.getFunctionManager();
        int funcCount = funcMgr.getFunctionCount();
        println("🔧 Functions found: " + funcCount);
        
        // List first 10 functions
        println("\\n📋 First 10 functions:");
        FunctionIterator funcIter = funcMgr.getFunctions(true);
        int count = 0;
        while (funcIter.hasNext() && count < 10) {
            Function func = funcIter.next();
            println("  " + (count + 1) + ". " + func.getName() + " @ " + func.getEntryPoint());
            count++;
        }
        
        // Count symbols
        SymbolTable symTable = program.getSymbolTable();
        long symCount = symTable.getNumSymbols();
        println("\\n🏷️  Symbols found: " + symCount);
        
        println("\\n✅ MCP Test Analysis Complete!");
    }
}
'''
        
        script_path = self.test_dir / "MCPTestScript.java"
        with open(script_path, 'w') as f:
            f.write(script_content)
        
        print(f"📝 Created Ghidra script: {script_path}")
        return script_path
    
    def generate_test_report(self):
        """Generate a comprehensive test report"""
        print("\n" + "="*60)
        print("🧪 GHIDRA MCP DYLD TEST REPORT")
        print("="*60)
        
        # Environment info
        print("\n🌍 Environment:")
        print(f"  Working Directory: {self.test_dir}")
        print(f"  Platform: macOS (Apple Silicon)")
        
        # Check what's available
        frameworks = self.list_available_frameworks()
        
        if frameworks:
            # Analyze first framework
            fw = frameworks[0]
            self.analyze_framework_with_file_command(fw)
            self.extract_strings_sample(fw)
        
        # MCP Plugin info
        print(f"\n🔌 MCP Plugin:")
        if self.mcp_plugin_path.exists():
            size = self.mcp_plugin_path.stat().st_size / 1024  # KB
            print(f"  ✅ Built: {self.mcp_plugin_path} ({size:.1f} KB)")
        else:
            print(f"  ❌ Not found: {self.mcp_plugin_path}")
        
        # Create Ghidra script
        script_path = self.create_ghidra_project_script()
        
        print("\n🎯 Next Steps:")
        print("1. Start Ghidra: `ghidra`")
        print("2. Create new project in ~/ghidra-mcp-test/ghidra-projects/")
        print("3. Install MCP plugin from GhidraMCP/target/GhidraMCP-1.0-SNAPSHOT.zip")
        print("4. Import framework binary (e.g., frameworks/Foundation)")
        print("5. Run analysis and explore with MCP integration")
        print(f"6. Use test script: {script_path}")
        
        print("\n🔧 Manual Testing Commands:")
        print("```bash")
        print("# Extract more frameworks")
        print("dyldex -l /System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e | head -20")
        print("dyldex -e Security -o frameworks/Security /System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e")
        print("")
        print("# Start Ghidra")
        print("ghidra")
        print("```")
        
        print("\n" + "="*60)

def main():
    """Main test function"""
    print("🧪 Ghidra + MCP + DyldExtractor Test Suite")
    print("=" * 50)
    
    tester = GhidraMCPTester()
    
    # Check prerequisites
    if not tester.check_prerequisites():
        print("\n❌ Prerequisites not met. Please run setup commands first:")
        print("1. setup-mcp-bridge")
        print("2. Extract frameworks with dyldex")
        sys.exit(1)
    
    print("\n✅ All prerequisites met!")
    
    # Generate comprehensive report
    tester.generate_test_report()

if __name__ == "__main__":
    main()