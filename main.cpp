#include <emscripten.h>
#include <emscripten/html5.h>
#include <emscripten/bind.h>
#include <iostream>
#include <vector>
#include <string>
#include <memory>
#include <map>
#include <functional>

class WebOS {
private:
    struct Window {
        int id;
        std::string title;
        int x, y, width, height;
        bool minimized;
        std::string content;
        
        Window(int _id, const std::string& _title, int _x, int _y, int _w, int _h)
            : id(_id), title(_title), x(_x), y(_y), width(_w), height(_h), minimized(false) {}
    };
    
    struct File {
        std::string name;
        std::string content;
        bool isDirectory;
        std::vector<std::shared_ptr<File>> children;
        
        File(const std::string& _name, bool _isDir = false) 
            : name(_name), isDirectory(_isDir) {}
    };
    
    std::vector<std::shared_ptr<Window>> windows;
    std::shared_ptr<File> rootDirectory;
    std::shared_ptr<File> currentDirectory;
    int nextWindowId;
    std::string currentTime;
    
public:
    WebOS() : nextWindowId(1) {
        initializeFileSystem();
        updateTime();
    }
    
    void initializeFileSystem() {
        rootDirectory = std::make_shared<File>("root", true);
        currentDirectory = rootDirectory;
        
        // Create some default directories and files
        auto documents = std::make_shared<File>("Documents", true);
        auto desktop = std::make_shared<File>("Desktop", true);
        auto system = std::make_shared<File>("System", true);
        
        auto readme = std::make_shared<File>("README.txt");
        readme->content = "Welcome to WebOS!\n\nThis is a simple web-based operating system built with C++ and WebAssembly.\n\nFeatures:\n- File Manager\n- Text Editor\n- Calculator\n- Terminal\n- Desktop Environment";
        
        auto config = std::make_shared<File>("config.sys");
        config->content = "# WebOS Configuration\nversion=1.0\nauthor=WebOS Team\n";
        
        documents->children.push_back(readme);
        system->children.push_back(config);
        
        rootDirectory->children.push_back(documents);
        rootDirectory->children.push_back(desktop);
        rootDirectory->children.push_back(system);
    }
    
    void updateTime() {
        // This would normally get system time, but for demo we'll use a placeholder
        currentTime = "12:34 PM";
    }
    
    int createWindow(const std::string& title, int x, int y, int width, int height) {
        auto window = std::make_shared<Window>(nextWindowId++, title, x, y, width, height);
        windows.push_back(window);
        return window->id;
    }
    
    void closeWindow(int windowId) {
        windows.erase(
            std::remove_if(windows.begin(), windows.end(),
                [windowId](const std::shared_ptr<Window>& w) { return w->id == windowId; }),
            windows.end()
        );
    }
    
    void moveWindow(int windowId, int x, int y) {
        for (auto& window : windows) {
            if (window->id == windowId) {
                window->x = x;
                window->y = y;
                break;
            }
        }
    }
    
    std::string getDesktopHTML() {
        std::string html = R"(
            <div id="desktop" class="desktop">
                <div class="taskbar">
                    <div class="start-menu">
                        <button onclick="toggleStartMenu()" class="start-button">Start</button>
                        <div id="startMenu" class="start-menu-content">
                            <div onclick="openFileManager()" class="menu-item">📁 File Manager</div>
                            <div onclick="openTextEditor()" class="menu-item">📝 Text Editor</div>
                            <div onclick="openCalculator()" class="menu-item">🧮 Calculator</div>
                            <div onclick="openTerminal()" class="menu-item">💻 Terminal</div>
                            <div onclick="openAbout()" class="menu-item">ℹ️ About</div>
                        </div>
                    </div>
                    <div class="taskbar-center">
                        <div id="windowButtons"></div>
                    </div>
                    <div class="taskbar-right">
                        <span class="time">)" + currentTime + R"(</span>
                    </div>
                </div>
                <div class="desktop-icons">
                    <div class="desktop-icon" ondblclick="openFileManager()">
                        <div class="icon">📁</div>
                        <div class="icon-label">File Manager</div>
                    </div>
                    <div class="desktop-icon" ondblclick="openTextEditor()">
                        <div class="icon">📝</div>
                        <div class="icon-label">Text Editor</div>
                    </div>
                    <div class="desktop-icon" ondblclick="openCalculator()">
                        <div class="icon">🧮</div>
                        <div class="icon-label">Calculator</div>
                    </div>
                </div>
            </div>
        )";
        
        // Add windows
        for (const auto& window : windows) {
            if (!window->minimized) {
                html += getWindowHTML(*window);
            }
        }
        
        return html;
    }
    
    std::string getWindowHTML(const Window& window) {
        return R"(
            <div class="window" id="window)" + std::to_string(window.id) + R"(" 
                 style="left: )" + std::to_string(window.x) + R"(px; top: )" + std::to_string(window.y) + R"(px; 
                        width: )" + std::to_string(window.width) + R"(px; height: )" + std::to_string(window.height) + R"(px;">
                <div class="window-header" onmousedown="startDrag()" + std::to_string(window.id) + R"()">
                    <span class="window-title">)" + window.title + R"(</span>
                    <div class="window-controls">
                        <button onclick="minimizeWindow()" + std::to_string(window.id) + R"()" class="window-btn">−</button>
                        <button onclick="closeWindow()" + std::to_string(window.id) + R"()" class="window-btn">×</button>
                    </div>
                </div>
                <div class="window-content">
                    )" + getWindowContent(window) + R"(
                </div>
            </div>
        )";
    }
    
    std::string getWindowContent(const Window& window) {
        if (window.title == "File Manager") {
            return getFileManagerContent();
        } else if (window.title == "Text Editor") {
            return getTextEditorContent();
        } else if (window.title == "Calculator") {
            return getCalculatorContent();
        } else if (window.title == "Terminal") {
            return getTerminalContent();
        } else if (window.title == "About") {
            return getAboutContent();
        }
        return "<p>Window content</p>";
    }
    
    std::string getFileManagerContent() {
        std::string content = R"(
            <div class="file-manager">
                <div class="file-toolbar">
                    <button onclick="navigateUp()">↑ Up</button>
                    <span class="current-path">)" + getCurrentPath() + R"(</span>
                </div>
                <div class="file-list">
        )";
        
        for (const auto& file : currentDirectory->children) {
            std::string icon = file->isDirectory ? "📁" : "📄";
            content += R"(<div class="file-item" ondblclick="openFile(')" + file->name + R"(')">)" +
                      icon + " " + file->name + "</div>";
        }
        
        content += "</div></div>";
        return content;
    }
    
    std::string getTextEditorContent() {
        return R"(
            <div class="text-editor">
                <div class="editor-toolbar">
                    <button onclick="newFile()">New</button>
                    <button onclick="saveFile()">Save</button>
                    <button onclick="openFile()">Open</button>
                </div>
                <textarea id="textEditor" class="editor-textarea" placeholder="Start typing..."></textarea>
            </div>
        )";
    }
    
    std::string getCalculatorContent() {
        return R"(
            <div class="calculator">
                <div class="calc-display">
                    <input type="text" id="calcDisplay" readonly>
                </div>
                <div class="calc-buttons">
                    <button onclick="clearCalc()" class="calc-btn">C</button>
                    <button onclick="calcInput('/')" class="calc-btn">÷</button>
                    <button onclick="calcInput('*')" class="calc-btn">×</button>
                    <button onclick="deleteLast()" class="calc-btn">⌫</button>
                    
                    <button onclick="calcInput('7')" class="calc-btn">7</button>
                    <button onclick="calcInput('8')" class="calc-btn">8</button>
                    <button onclick="calcInput('9')" class="calc-btn">9</button>
                    <button onclick="calcInput('-')" class="calc-btn">−</button>
                    
                    <button onclick="calcInput('4')" class="calc-btn">4</button>
                    <button onclick="calcInput('5')" class="calc-btn">5</button>
                    <button onclick="calcInput('6')" class="calc-btn">6</button>
                    <button onclick="calcInput('+')" class="calc-btn">+</button>
                    
                    <button onclick="calcInput('1')" class="calc-btn">1</button>
                    <button onclick="calcInput('2')" class="calc-btn">2</button>
                    <button onclick="calcInput('3')" class="calc-btn">3</button>
                    <button onclick="calculate()" class="calc-btn calc-equals" rowspan="2">=</button>
                    
                    <button onclick="calcInput('0')" class="calc-btn calc-zero">0</button>
                    <button onclick="calcInput('.')" class="calc-btn">.</button>
                </div>
            </div>
        )";
    }
    
    std::string getTerminalContent() {
        return R"(
            <div class="terminal">
                <div id="terminalOutput" class="terminal-output">
                    WebOS Terminal v1.0<br>
                    Type 'help' for available commands.<br>
                    <br>
                </div>
                <div class="terminal-input">
                    <span class="terminal-prompt">webos@system:~$ </span>
                    <input type="text" id="terminalInput" class="terminal-input-field" onkeypress="handleTerminalInput(event)">
                </div>
            </div>
        )";
    }
    
    std::string getAboutContent() {
        return R"(
            <div class="about">
                <h2>WebOS</h2>
                <p><strong>Version:</strong> 1.0</p>
                <p><strong>Built with:</strong> C++ and WebAssembly</p>
                <p><strong>Description:</strong> A web-based operating system simulation</p>
                <br>
                <p>Features:</p>
                <ul>
                    <li>Desktop Environment</li>
                    <li>File Manager</li>
                    <li>Text Editor</li>
                    <li>Calculator</li>
                    <li>Terminal</li>
                    <li>Window Management</li>
                </ul>
            </div>
        )";
    }
    
    std::string getCurrentPath() {
        return "/root"; // Simplified for demo
    }
    
    void executeCommand(const std::string& command) {
        // Basic terminal commands implementation
        EM_ASM({
            var cmd = UTF8ToString($0);
            var output = document.getElementById('terminalOutput');
            output.innerHTML += 'webos@system:~$ ' + cmd + '<br>';
            
            if (cmd === 'help') {
                output.innerHTML += 'Available commands:<br>help - Show this help<br>ls - List files<br>pwd - Show current directory<br>clear - Clear terminal<br>';
            } else if (cmd === 'ls') {
                output.innerHTML += 'Documents  Desktop  System<br>';
            } else if (cmd === 'pwd') {
                output.innerHTML += '/root<br>';
            } else if (cmd === 'clear') {
                output.innerHTML = 'WebOS Terminal v1.0<br>Type \'help\' for available commands.<br><br>';
            } else {
                output.innerHTML += 'Command not found: ' + cmd + '<br>';
            }
            output.innerHTML += '<br>';
            output.scrollTop = output.scrollHeight;
        }, command.c_str());
    }
};

// Global WebOS instance
WebOS* webos = nullptr;

extern "C" {
    EMSCRIPTEN_KEEPALIVE
    void initWebOS() {
        webos = new WebOS();
    }
    
    EMSCRIPTEN_KEEPALIVE
    const char* getDesktopHTML() {
        static std::string html;
        if (webos) {
            html = webos->getDesktopHTML();
            return html.c_str();
        }
        return "";
    }
    
    EMSCRIPTEN_KEEPALIVE
    int openWindow(const char* title, int x, int y, int width, int height) {
        if (webos) {
            return webos->createWindow(std::string(title), x, y, width, height);
        }
        return -1;
    }
    
    EMSCRIPTEN_KEEPALIVE
    void closeWindowById(int windowId) {
        if (webos) {
            webos->closeWindow(windowId);
        }
    }
    
    EMSCRIPTEN_KEEPALIVE
    void executeTerminalCommand(const char* command) {
        if (webos) {
            webos->executeCommand(std::string(command));
        }
    }
}

int main() {
    initWebOS();
    return 0;
}
