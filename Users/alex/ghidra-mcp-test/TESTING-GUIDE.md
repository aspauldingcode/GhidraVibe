# 🧪 Ghidra + MCP + DyldExtractor Testing Guide

## 🚀 **QUICK START** (Do this first!)

```bash
# 1. Go to the RIGHT directory
cd ~/ghidra-mcp-test

# 2. Enter Nix environment  
nix develop /Users/alex/GhidraMCP_Vibe_RSE

# 3. Run test (use 'python', not 'python3')
python test-ghidra-mcp-workflow.py

# 4. Start Ghidra
ghidra
```

## 🔧 **Additional Commands Available**

### **Framework Extraction Commands**
```bash
# List all available frameworks in the dyld cache
dyldex -l /System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e | head -20

# Extract specific frameworks for analysis
dyldex -e CoreFoundation -o frameworks/CoreFoundation /System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e
dyldex -e IOKit -o frameworks/IOKit /System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e
dyldex -e CoreGraphics -o frameworks/CoreGraphics /System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e
dyldex -e Network -o frameworks/Network /System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e

# Extract ALL frameworks (warning: takes a long time and lots of space!)
dyldex_all /System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e -o frameworks/
```

### **Setup & Maintenance Commands**
```bash
# Re-run MCP bridge setup (if you need to rebuild)
setup-mcp-bridge

# Complete environment setup
setup-ghidra-mcp-vibe

# Extract dyld cache (automated workflow)
extract-dyld-cache
```

### **Analysis & Investigation Commands**
```bash
# Analyze extracted frameworks
file frameworks/*
strings frameworks/Foundation | grep -i "class\|method\|function" | head -10
otool -L frameworks/Security  # Show library dependencies
nm frameworks/Foundation | head -20  # Show symbols

# Check what's in your frameworks directory
ls -lah frameworks/
du -sh frameworks/*  # Check sizes
```

### **Testing & Verification Commands**
```bash
# Run the comprehensive test again
python test-ghidra-mcp-workflow.py

# Check if tools are working
which ghidra
which dyldex
which python
java -version
python --version

# Verify MCP plugin build
ls -la GhidraMCP/target/
```

### **Environment Information**
```bash
# Show environment details
env | grep -E "(JAVA|PYTHON|GHIDRA|NIX)"
echo $PATH
echo $PYTHONPATH

# Show available disk space (frameworks can be large!)
df -h .
```

## 🎯 **Recommended Workflow**

1. **Extract more frameworks**:
   ```bash
   dyldex -e CoreFoundation -o frameworks/CoreFoundation /System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e
   ```

2. **Launch Ghidra**:
   ```bash
   ghidra
   ```

3. **In parallel terminal** (while Ghidra loads), analyze frameworks:
   ```bash
   file frameworks/*
   strings frameworks/CoreFoundation | grep -i "CF" | head -10
   ```

## 🚀 **Pro Tips**

- **Extract frameworks gradually** - they're large files
- **Use `file` command** to verify framework architecture before importing to Ghidra
- **Check framework dependencies** with `otool -L` to understand relationships
- **Monitor disk space** - frameworks can take several GB

---

## ✅ **Current Status**
- **Ghidra**: ✅ Available (v11.3.2)
- **MCP Plugin**: ✅ Built successfully (27.0 KB)
- **DyldExtractor**: ✅ Working
- **Frameworks**: ✅ Foundation extracted (10.0 MB)

## 🚀 **Step-by-Step Testing Workflow**

### **Phase 1: Environment Verification**

**🚨 IMPORTANT: You MUST be in the correct directory!**

```bash
# STEP 1: Navigate to the test directory (NOT the flake directory!)
cd ~/ghidra-mcp-test

# STEP 2: Enter the Nix development environment
nix develop /Users/alex/GhidraMCP_Vibe_RSE

# STEP 3: Run the test script (note: use 'python', not 'python3')
python test-ghidra-mcp-workflow.py
```

**❌ WRONG**: Running from `/Users/alex/GhidraMCP_Vibe_RSE` (the flake directory)  
**✅ CORRECT**: Running from `~/ghidra-mcp-test` (the test directory)

### **Phase 2: Extract Additional Frameworks**
```bash
# List available frameworks in dyld cache
dyldex -l /System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e | head -20

# Extract Security framework (good for crypto analysis)
dyldex -e Security -o frameworks/Security /System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e

# Extract CoreFoundation (fundamental framework)
dyldex -e CoreFoundation -o frameworks/CoreFoundation /System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e

# Extract IOKit (kernel interface)
dyldex -e IOKit -o frameworks/IOKit /System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e
```

### **Phase 3: Ghidra Setup & Analysis**

#### **3.1 Start Ghidra**
```bash
ghidra
```

#### **3.2 Create New Project**
1. **File** → **New Project**
2. Choose **Non-Shared Project**
3. Project Directory: `~/ghidra-mcp-test/ghidra-projects`
4. Project Name: `MacOS-MCP-Analysis`

#### **3.3 Install MCP Plugin**
1. **File** → **Install Extensions**
2. Click **+** (Add Extension)
3. Navigate to: `~/ghidra-mcp-test/GhidraMCP/target/GhidraMCP-1.0-SNAPSHOT.zip`
4. Install and restart Ghidra

#### **3.4 Import Framework**
1. **File** → **Import File**
2. Select: `~/ghidra-mcp-test/frameworks/Foundation`
3. Format: **Mach-O**
4. Click **OK** and **OK** again

#### **3.5 Analyze Binary**
1. Double-click the imported Foundation binary
2. When prompted, click **Yes** to analyze
3. Use **default analysis options**
4. Wait for analysis to complete

### **Phase 4: MCP Integration Testing**

#### **4.1 Verify MCP Plugin**
- Check **Window** menu for MCP-related options
- Look for MCP toolbar buttons
- Check **Tools** → **MCP** menu

#### **4.2 Test MCP Features**
1. **Function Analysis**: Select a function and test MCP context
2. **Symbol Resolution**: Test MCP symbol lookup
3. **Cross-References**: Use MCP for xref analysis
4. **Decompiler Integration**: Test MCP in decompiler view

#### **4.3 Run Test Script**
1. **Window** → **Script Manager**
2. **Script Directories** → Add: `~/ghidra-mcp-test/`
3. Run `MCPTestScript.java`
4. Check console output

### **Phase 5: Advanced Testing**

#### **5.1 Objective-C Analysis**
```bash
# Foundation contains lots of Objective-C classes
# Test MCP with:
# - Class hierarchy analysis
# - Method signature parsing
# - Protocol analysis
```

#### **5.2 ARM64e Features**
```bash
# Test Apple Silicon specific features:
# - Pointer Authentication (PAC)
# - Branch Target Identification (BTI)
# - Memory Tagging Extensions (MTE)
```

#### **5.3 Cross-Framework Analysis**
```bash
# Import multiple frameworks and test:
# - Cross-framework function calls
# - Shared symbol resolution
# - Framework dependency analysis
```

## 🔍 **Key Testing Areas**

### **1. MCP Context Understanding**
- **Test**: Ask MCP to explain complex ARM64e assembly
- **Expected**: Detailed explanation of instructions and calling conventions

### **2. Symbol Resolution**
- **Test**: Use MCP to resolve unknown symbols
- **Expected**: Accurate symbol identification and documentation

### **3. Function Analysis**
- **Test**: MCP analysis of Objective-C methods
- **Expected**: Understanding of method signatures, parameters, return types

### **4. Security Analysis**
- **Test**: MCP identification of security-relevant code
- **Expected**: Recognition of crypto functions, validation routines, etc.

## 📊 **Expected Results**

### **Foundation Framework Analysis**
- **Functions**: ~50,000+ functions
- **Symbols**: ~500,000+ symbols
- **Classes**: ~5,000+ Objective-C classes
- **Protocols**: ~1,000+ protocols

### **MCP Integration**
- **Context Awareness**: MCP should understand macOS/iOS specific patterns
- **Symbol Knowledge**: Recognition of Apple frameworks and APIs
- **Architecture Understanding**: ARM64e instruction set knowledge

## 🐛 **Troubleshooting**

### **Common Issues**
1. **MCP Plugin Not Loading**
   - Check Ghidra logs: `Help` → `Ghidra User Guide` → `Logging`
   - Verify plugin in: `Help` → `About Ghidra` → `Extensions`

2. **Framework Import Fails**
   - Verify file format with: `file frameworks/Foundation`
   - Check Ghidra import logs

3. **Analysis Hangs**
   - Reduce analysis options for large binaries
   - Use incremental analysis

### **Performance Tips**
- Start with smaller frameworks (IOKit, Security)
- Disable unnecessary analyzers for initial testing
- Use Ghidra's headless mode for batch processing

## 🎯 **Success Criteria**

✅ **Basic Integration**
- [ ] MCP plugin loads without errors
- [ ] Framework imports successfully
- [ ] Basic analysis completes

✅ **MCP Functionality**
- [ ] MCP provides contextual help
- [ ] Symbol resolution works
- [ ] Cross-reference analysis functions

✅ **Advanced Features**
- [ ] Objective-C class analysis
- [ ] ARM64e instruction understanding
- [ ] Multi-framework analysis

## 📝 **Test Results Log**

Create a log file to track your testing:
```bash
echo "$(date): Starting Ghidra MCP testing" >> test-results.log
# Add results as you test each feature
```

---

**🎉 Ready to test!** Start with Phase 1 and work through each phase systematically.